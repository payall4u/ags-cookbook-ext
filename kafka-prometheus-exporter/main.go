package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/IBM/sarama"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// KafkaMessage 对应云监控数据传输推送到 Kafka 的消息格式
type KafkaMessage struct {
	Namespace   string      `json:"Namespace"`
	Measurement string      `json:"Measurement"`
	Dimensions  []Dimension `json:"Dimensions"`
	Metrics     []Metric    `json:"Metrics"`
}

type Dimension struct {
	Name  string `json:"Name"`
	Value string `json:"Value"`
}

type Metric struct {
	MetricName string  `json:"MetricName"`
	Statistic  string  `json:"Statistic"`
	Period     int     `json:"Period"`
	Timestamp  int64   `json:"Timestamp"`
	Value      float64 `json:"Value"`
}

var metricNameMapping = map[string]string{
	"SandboxCpuUsagePercent":         "ags_sandbox_cpu_usage_percent",
	"SandboxCpuUsedCores":            "ags_sandbox_cpu_used_cores",
	"SandboxDiskReadBytesPerSecond":  "ags_sandbox_disk_read_bytes_per_second",
	"SandboxDiskWriteBytesPerSecond": "ags_sandbox_disk_write_bytes_per_second",
	"SandboxFsUsagePercent":          "ags_sandbox_fs_usage_percent",
	"SandboxFsUsedBytes":             "ags_sandbox_fs_used_bytes",
	"SandboxMemoryUsagePercent":      "ags_sandbox_memory_usage_percent",
	"SandboxMemoryUsedBytes":         "ags_sandbox_memory_used_bytes",
	"SandboxNetworkRxBytesPerSecond": "ags_sandbox_network_rx_bytes_per_second",
	"SandboxNetworkTxBytesPerSecond": "ags_sandbox_network_tx_bytes_per_second",
}

// MetricsCollector 管理 Prometheus 指标及生命周期
type MetricsCollector struct {
	mu         sync.RWMutex
	gauges     map[string]*prometheus.GaugeVec
	registry   *prometheus.Registry
	msgCounter *prometheus.CounterVec
	lastSeen   map[string]time.Time
	ttl        time.Duration
}

func NewMetricsCollector(ttl time.Duration) *MetricsCollector {
	registry := prometheus.NewRegistry()
	mc := &MetricsCollector{
		gauges:   make(map[string]*prometheus.GaugeVec),
		registry: registry,
		lastSeen: make(map[string]time.Time),
		ttl:      ttl,
	}

	labels := []string{"appid", "instance_id", "tool_id", "statistic"}
	for _, promName := range metricNameMapping {
		gauge := prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: promName,
			Help: fmt.Sprintf("AGS sandbox metric: %s", promName),
		}, labels)
		registry.MustRegister(gauge)
		mc.gauges[promName] = gauge
	}

	mc.msgCounter = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "ags_kafka_consumer_messages_total",
		Help: "Total number of messages consumed from Kafka",
	}, []string{"topic", "partition", "status"})
	registry.MustRegister(mc.msgCounter)

	return mc
}

func (mc *MetricsCollector) ProcessMessage(msg *KafkaMessage) {
	var appid, instanceID, toolID string
	for _, d := range msg.Dimensions {
		switch d.Name {
		case "appid":
			appid = d.Value
		case "instance_id":
			instanceID = d.Value
		case "tool_id":
			toolID = d.Value
		}
	}

	for _, m := range msg.Metrics {
		promName, ok := metricNameMapping[m.MetricName]
		if !ok {
			log.Printf("WARN: unknown metric %q, skipping", m.MetricName)
			continue
		}
		mc.mu.RLock()
		gauge := mc.gauges[promName]
		mc.mu.RUnlock()
		gauge.WithLabelValues(appid, instanceID, toolID, strings.ToLower(m.Statistic)).Set(m.Value)
	}

	if mc.ttl > 0 {
		key := fmt.Sprintf("%s/%s/%s", appid, instanceID, toolID)
		mc.mu.Lock()
		mc.lastSeen[key] = time.Now()
		mc.mu.Unlock()
	}
}

// CleanupStaleSandboxes 定期清理长时间无数据的沙箱指标，避免 Prometheus series 持续膨胀
func (mc *MetricsCollector) CleanupStaleSandboxes(ctx context.Context) {
	if mc.ttl == 0 {
		return
	}
	ticker := time.NewTicker(mc.ttl / 2)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			now := time.Now()
			mc.mu.Lock()
			for key, ts := range mc.lastSeen {
				if now.Sub(ts) > mc.ttl {
					parts := strings.SplitN(key, "/", 3)
					if len(parts) == 3 {
						appid, instanceID, toolID := parts[0], parts[1], parts[2]
						for _, gauge := range mc.gauges {
							for _, stat := range []string{"avg", "max", "min", "last"} {
								gauge.DeleteLabelValues(appid, instanceID, toolID, stat)
							}
						}
					}
					delete(mc.lastSeen, key)
					log.Printf("INFO: cleaned up stale metrics for %s", key)
				}
			}
			mc.mu.Unlock()
		}
	}
}

// ConsumerGroupHandler 实现 sarama.ConsumerGroupHandler
type ConsumerGroupHandler struct {
	collector *MetricsCollector
	topic     string
}

func (h *ConsumerGroupHandler) Setup(_ sarama.ConsumerGroupSession) error   { return nil }
func (h *ConsumerGroupHandler) Cleanup(_ sarama.ConsumerGroupSession) error { return nil }

func (h *ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for msg := range claim.Messages() {
		partition := fmt.Sprintf("%d", claim.Partition())
		var kafkaMsg KafkaMessage
		if err := json.Unmarshal(msg.Value, &kafkaMsg); err != nil {
			log.Printf("ERROR: unmarshal failed offset=%d partition=%d: %v", msg.Offset, msg.Partition, err)
			h.collector.msgCounter.WithLabelValues(h.topic, partition, "error").Inc()
			session.MarkMessage(msg, "")
			continue
		}
		h.collector.ProcessMessage(&kafkaMsg)
		h.collector.msgCounter.WithLabelValues(h.topic, partition, "ok").Inc()
		session.MarkMessage(msg, "")
	}
	return nil
}

func buildKafkaConfig() *sarama.Config {
	config := sarama.NewConfig()
	config.Version = sarama.V2_8_1_0
	config.Consumer.Group.Rebalance.GroupStrategies = []sarama.BalanceStrategy{
		sarama.NewBalanceStrategyRoundRobin(),
	}

	if getEnv("KAFKA_OFFSET_NEWEST", "false") == "true" {
		config.Consumer.Offsets.Initial = sarama.OffsetNewest
	} else {
		config.Consumer.Offsets.Initial = sarama.OffsetOldest
	}

	if getEnv("KAFKA_SASL_ENABLE", "false") == "true" {
		config.Net.SASL.Enable = true
		config.Net.SASL.Mechanism = sarama.SASLTypePlaintext
		config.Net.SASL.User = getEnv("KAFKA_SASL_USER", "")
		config.Net.SASL.Password = getEnv("KAFKA_SASL_PASSWORD", "")
	}

	if getEnv("KAFKA_TLS_ENABLE", "false") == "true" {
		config.Net.TLS.Enable = true
		config.Net.TLS.Config = &tls.Config{InsecureSkipVerify: false}
	}

	return config
}

func main() {
	brokers := getEnv("KAFKA_BROKERS", "")
	if brokers == "" {
		log.Fatal("FATAL: KAFKA_BROKERS is required")
	}
	topic := getEnv("KAFKA_TOPIC", "ags-monitor")
	group := getEnv("KAFKA_GROUP", "ags-prometheus-exporter")
	listenAddr := getEnv("LISTEN_ADDR", ":8080")
	ttlSeconds := parseInt(getEnv("METRIC_TTL_SECONDS", "300"))

	log.Printf("Starting AGS Kafka Prometheus Exporter")
	log.Printf("  Brokers:    %s", brokers)
	log.Printf("  Topic:      %s", topic)
	log.Printf("  Group:      %s", group)
	log.Printf("  Metric TTL: %ds", ttlSeconds)

	collector := NewMetricsCollector(time.Duration(ttlSeconds) * time.Second)

	client, err := sarama.NewConsumerGroup(strings.Split(brokers, ","), group, buildKafkaConfig())
	if err != nil {
		log.Fatalf("FATAL: failed to create consumer group: %v", err)
	}
	defer client.Close()

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(collector.registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		select {
		case err := <-client.Errors():
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, "kafka error: %v", err)
		default:
			w.WriteHeader(http.StatusOK)
			fmt.Fprint(w, "OK")
		}
	})

	httpServer := &http.Server{Addr: listenAddr, Handler: mux}
	go func() {
		log.Printf("Metrics server listening on %s", listenAddr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("FATAL: HTTP server: %v", err)
		}
	}()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go collector.CleanupStaleSandboxes(ctx)

	handler := &ConsumerGroupHandler{collector: collector, topic: topic}

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		backoff := time.Second
		for {
			if err := client.Consume(ctx, []string{topic}, handler); err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("WARN: consumer error: %v, retrying in %s", err, backoff)
				select {
				case <-ctx.Done():
					return
				case <-time.After(backoff):
				}
				if backoff < 60*time.Second {
					backoff *= 2
				}
				continue
			}
			backoff = time.Second
			if ctx.Err() != nil {
				return
			}
		}
	}()

	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)
	<-sigchan

	log.Println("Shutting down...")
	cancel()
	wg.Wait()

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	httpServer.Shutdown(shutdownCtx)
	log.Println("Stopped.")
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

func parseInt(s string) int {
	var v int
	fmt.Sscanf(s, "%d", &v)
	return v
}
