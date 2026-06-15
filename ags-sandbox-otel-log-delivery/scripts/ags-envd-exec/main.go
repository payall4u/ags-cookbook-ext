package main

import (
	"context"
	"fmt"
	"os"
	"time"

	code "github.com/TencentCloudAgentRuntime/ags-go-sdk/sandbox/code"
	"github.com/TencentCloudAgentRuntime/ags-go-sdk/tool/command"
	"github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common"
)

func main() {
	instanceID := os.Getenv("INSTANCE_ID")
	cmd := os.Getenv("COMMAND")
	if instanceID == "" || cmd == "" {
		fatalf("INSTANCE_ID and COMMAND are required")
	}

	secretID := os.Getenv("TENCENTCLOUD_SECRET_ID")
	secretKey := os.Getenv("TENCENTCLOUD_SECRET_KEY")
	if secretID == "" || secretKey == "" {
		fatalf("TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY are required")
	}

	region := getenvDefault("TENCENTCLOUD_REGION", "ap-guangzhou")
	user := getenvDefault("COMMAND_USER", "root")
	timeout := getenvDurationDefault("COMMAND_TIMEOUT", 120*time.Second)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	var credential common.CredentialIface
	if token := os.Getenv("TENCENTCLOUD_TOKEN"); token != "" {
		credential = common.NewTokenCredential(secretID, secretKey, token)
	} else {
		credential = common.NewCredential(secretID, secretKey)
	}
	sandbox, err := code.Connect(ctx, instanceID, code.WithCredential(credential), code.WithRegion(region))
	if err != nil {
		fatalf("connect sandbox: %v", err)
	}

	result, err := sandbox.Commands.Run(ctx, cmd, &command.ProcessConfig{User: user}, nil)
	if err != nil {
		fatalf("run command through envd: %v", err)
	}

	if len(result.Stdout) > 0 {
		_, _ = os.Stdout.Write(result.Stdout)
	}
	if len(result.Stderr) > 0 {
		_, _ = os.Stderr.Write(result.Stderr)
	}
	if result.Error != nil {
		fmt.Fprintln(os.Stderr, *result.Error)
	}
	if result.ExitCode != 0 {
		os.Exit(int(result.ExitCode))
	}
}

func getenvDefault(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func getenvDurationDefault(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		fatalf("invalid %s duration %q: %v", key, value, err)
	}
	return parsed
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
