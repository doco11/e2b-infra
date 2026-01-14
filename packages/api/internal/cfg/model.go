package cfg

import (
	"fmt"

	"github.com/caarlos0/env/v11"
)

const (
	DefaultKernelVersion = "vmlinux-6.1.158"
)

type Config struct {
	AdminToken string `env:"ADMIN_TOKEN"`

	AnalyticsCollectorAPIToken string `env:"ANALYTICS_COLLECTOR_API_TOKEN"`
	AnalyticsCollectorHost     string `env:"ANALYTICS_COLLECTOR_HOST"`

	ClickhouseConnectionString string `env:"CLICKHOUSE_CONNECTION_STRING"`

	E2BLiteMode bool `env:"E2B_LITE_MODE" envDefault:"false"`

	LokiPassword string `env:"LOKI_PASSWORD"`
	LokiURL      string `env:"LOKI_URL"` // Required in production, optional in lite mode
	LokiUser     string `env:"LOKI_USER"`

	NomadAddress string `env:"NOMAD_ADDRESS" envDefault:"http://localhost:4646"`
	NomadToken   string `env:"NOMAD_TOKEN"`

	PostgresConnectionString string `env:"POSTGRES_CONNECTION_STRING,required,notEmpty"`

	PosthogAPIKey string `env:"POSTHOG_API_KEY"`

	RedisURL         string `env:"REDIS_URL"`
	RedisClusterURL  string `env:"REDIS_CLUSTER_URL"`
	RedisTLSCABase64 string `env:"REDIS_TLS_CA_BASE64"`

	SandboxAccessTokenHashSeed string `env:"SANDBOX_ACCESS_TOKEN_HASH_SEED"`

	// SupabaseJWTSecrets is a list of secrets used to verify the Supabase JWT.
	// More secrets are possible in the case of JWT secret rotation where we need to accept
	// tokens signed with the old secret for some time.
	SupabaseJWTSecrets []string `env:"SUPABASE_JWT_SECRETS"`

	DefaultKernelVersion string `env:"DEFAULT_KERNEL_VERSION"`
}

func Parse() (Config, error) {
	var config Config
	err := env.Parse(&config)
	if err != nil {
		return config, err
	}

	if config.DefaultKernelVersion == "" {
		config.DefaultKernelVersion = DefaultKernelVersion
	}

	// In lite mode, some required fields become optional
	if !config.E2BLiteMode {
		if config.LokiURL == "" {
			return config, fmt.Errorf("environment variable LOKI_URL is required when E2B_LITE_MODE is not enabled")
		}
	}

	return config, nil
}
