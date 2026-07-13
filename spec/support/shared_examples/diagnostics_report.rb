# frozen_string_literal: true

# Behavioural examples for the `lago:diagnostics` diagnostic report.
#
# Shared by the `Lago::Diagnostics` class spec and the `lago:diagnostics`
# rake task spec so both surfaces are exercised against the same report
# content.
#
# The host must define:
# - `let(:report)`: runs the diagnostic and returns the full output string.
#   It must be lazily evaluated so the `before` stubs below apply first.
# - a stub of the ClickHouse connection, which is unavailable in specs.
RSpec.shared_examples "a lago diagnostics report" do
  it "prints the banners and all ten section headers" do
    expect(report).to include("LAGO SUPPORT DIAGNOSTIC")
    expect(report).to include("1. VERSION AND BUILD")
    expect(report).to include("2. ENVIRONMENT")
    expect(report).to include("3. CONFIGURATION")
    expect(report).to include("4. DATABASE")
    expect(report).to include("5. REDIS")
    expect(report).to include("6. CLICKHOUSE")
    expect(report).to include("7. KAFKA")
    expect(report).to include("8. SMTP")
    expect(report).to include("9. DATA SHAPE")
    expect(report).to include("10. RECENT ERRORS")
    expect(report).to include("END OF DIAGNOSTIC")
  end

  it "lists every payment provider and integration" do
    %w[Adyen Cashfree Flutterwave Gocardless Moneyhash Stripe].each do |name|
      expect(report).to match(/^    #{Regexp.escape(name)}\s+: (enabled|disabled)$/)
    end

    ["Anrok (tax)", "Avalara (tax)", "Hubspot", "Netsuite", "Okta (SSO)", "Salesforce", "Xero"].each do |name|
      expect(report).to match(/^    #{Regexp.escape(name)}\s+: (enabled|disabled)$/)
    end
  end

  context "with premium integrations enabled on an organization" do
    before { create(:organization, premium_integrations: %w[netsuite revenue_analytics]) }

    it "lists every premium integration with a per-org count" do
      expect(report).to include("## Premium Integrations (orgs with each enabled)")
      expect(report).to match(/^    netsuite\s+: [1-9]\d*$/)
      expect(report).to match(/^    revenue_analytics\s+: [1-9]\d*$/)

      Organization::PREMIUM_INTEGRATIONS.each do |name|
        expect(report).to match(/^    #{Regexp.escape(name)}\s+: \d+$/)
      end
    end
  end

  context "when the feature flags file does not exist" do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Rails.root.join("app/config/feature_flags.yaml")).and_return(false)
    end

    it "skips the feature flags subsection and still completes" do
      expect(report).not_to include("## Feature Flags")
      expect(report).to include("## License")
      expect(report).to include("END OF DIAGNOSTIC")
    end
  end

  it "labels the row counts as estimated" do
    expect(report).to include("## Key Table Row Counts (estimated)")
  end

  context "when LAGO_VERSION contains a version tag instead of a SHA" do
    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(Rails.root.join("LAGO_VERSION")).and_return("v1.20.0\n")
    end

    it "does not label the tag as a commit SHA" do
      expect(report).to include("Commit SHA     : (not available, version tag build)")
    end
  end

  context "when LAGO_VERSION contains a git commit SHA" do
    let(:sha) { "0f425aee1b9e7c927eb9559055fd1d11708bc7b5" }

    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(Rails.root.join("LAGO_VERSION")).and_return("#{sha}\n")
    end

    it "prints the SHA as the commit SHA" do
      expect(report).to include("Commit SHA     : #{sha}")
    end
  end

  context "when the LAGO_VERSION file cannot be read" do
    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(Rails.root.join("LAGO_VERSION")).and_raise(Errno::ENOENT)
    end

    it "prints the read error as the commit SHA" do
      expect(report).to match(/Commit SHA     : error: Errno::ENOENT/)
    end
  end

  context "when ClickHouse is not enabled" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_CLICKHOUSE_ENABLED").and_return(nil)
    end

    it "reports ClickHouse as disabled without probing it" do
      expect(report).to include("Enabled        : false")
      expect(report).not_to match(/^  Version        :/)
    end
  end

  context "when ClickHouse is enabled but unreachable" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_CLICKHOUSE_ENABLED").and_return("true")
    end

    it "prints an error marker on the ClickHouse version line" do
      expect(report).to include("Enabled        : true")
      expect(report).to match(/Version        : error:/)
    end
  end

  context "when Kafka is not configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return(nil)
    end

    it "reports Kafka as disabled without a bootstrap servers line" do
      expect(report).not_to match(/Bootstrap servers/)
    end
  end

  context "when Kafka is configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return("broker1:9092")
    end

    it "reports Kafka as enabled with the bootstrap servers" do
      expect(report).to match(/^    Bootstrap servers\s+: broker1:9092$/)
    end
  end

  context "when SMTP is not configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_SMTP_ADDRESS").and_return(nil)
    end

    it "reports SMTP as disabled without address and port lines" do
      expect(report).not_to include("Address        :")
      expect(report).not_to include("Port           :")
    end
  end

  context "when SMTP is configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_SMTP_ADDRESS").and_return("smtp.example.com")
      allow(ENV).to receive(:[]).with("LAGO_SMTP_PORT").and_return("587")
    end

    it "reports SMTP as enabled with address and port" do
      expect(report).to include("Address        : smtp.example.com")
      expect(report).to include("Port           : 587")
    end
  end

  context "when running on Kubernetes" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KUBERNETES_SERVICE_HOST").and_return("10.0.0.1")
    end

    it "detects a kubernetes deployment" do
      expect(report).to include("Deployment     : kubernetes")
    end
  end

  context "when running on Lago cloud" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KUBERNETES_SERVICE_HOST").and_return(nil)
      allow(ENV).to receive(:[]).with("LAGO_CLOUD").and_return("true")
    end

    it "detects a lago-cloud deployment" do
      expect(report).to include("Deployment     : lago-cloud")
    end
  end

  context "when running in a plain container" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KUBERNETES_SERVICE_HOST").and_return(nil)
      allow(ENV).to receive(:[]).with("LAGO_CLOUD").and_return(nil)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
    end

    it "detects a docker/container deployment" do
      expect(report).to include("Deployment     : docker/container")
    end
  end

  context "when no deployment marker is present" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KUBERNETES_SERVICE_HOST").and_return(nil)
      allow(ENV).to receive(:[]).with("LAGO_CLOUD").and_return(nil)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
    end

    it "reports the deployment as unknown" do
      expect(report).to include("Deployment     : unknown")
    end
  end

  context "with a secret environment variable set" do
    before { ENV["LAGO_SUPPORT_INFO_SPEC_TOKEN"] = "s3cr3t-value" }
    after { ENV.delete("LAGO_SUPPORT_INFO_SPEC_TOKEN") }

    it "redacts the value in the ENV dump" do
      expect(report).to include("LAGO_SUPPORT_INFO_SPEC_TOKEN=***")
      expect(report).not_to include("s3cr3t-value")
    end
  end

  context "when a probe raises" do
    before do
      allow(Sidekiq::Queue).to receive(:all).and_raise(StandardError, "redis is down")
    end

    it "prints an error marker and still completes the report" do
      expect { report }.not_to raise_error

      expect(report).to include("error: StandardError - redis is down")
      expect(report).to include("END OF DIAGNOSTIC")
    end
  end

  context "when the dead set contains wrapped ActiveJob entries" do
    let(:wrapped_entry) do
      {
        "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "BillSubscriptionJob",
        "error_class" => "BaseService::ForbiddenFailure",
        "failed_at" => Time.current.to_f
      }
    end
    let(:plain_entry) do
      {
        "class" => "PlainSidekiqJob",
        "error_class" => "StandardError",
        "failed_at" => Time.current.to_f
      }
    end

    before do
      allow(Sidekiq::DeadSet).to receive(:new).and_return([wrapped_entry, plain_entry])
    end

    it "prints the wrapped job class instead of the ActiveJob wrapper" do
      expect(report).to include("BillSubscriptionJob  [BaseService::ForbiddenFailure]")
      expect(report).to include("PlainSidekiqJob  [StandardError]")
      expect(report).not_to include("JobWrapper  [")
    end
  end

  context "when the Sidekiq dead set cannot be read" do
    before do
      allow(Sidekiq::DeadSet).to receive(:new).and_raise(StandardError, "dead set unavailable")
    end

    it "prints error markers and still renders the following sections" do
      expect { report }.not_to raise_error

      expect(report).to include("error: StandardError - dead set unavailable")
      expect(report).to include("6. CLICKHOUSE")
      expect(report).to include("## Key Table Row Counts (estimated)")
      expect(report).to include("10. RECENT ERRORS")
    end
  end

  context "with a stubbed log file" do
    let(:log_path) { Rails.root.join("log", "#{Rails.env}.log") }
    let(:log_file) { Tempfile.new("diagnostics_log") }

    before do
      log_file.write(log_content)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(log_path).and_return(true)
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(log_path).and_yield(log_file)
    end

    after { log_file.close! }

    context "when the log contains more matching lines than the limit" do
      let(:log_content) do
        lines = (1..105).map { |i| "ERROR line-#{format("%03d", i)}" }
        lines.insert(50, "INFO everything is fine")
        lines.join("\n") + "\n"
      end

      it "keeps only the last 100 ERROR/FATAL lines" do
        expect(report).to include("ERROR line-006")
        expect(report).to include("ERROR line-105")
        expect(report).not_to include("ERROR line-005")
        expect(report).not_to include("INFO everything is fine")
      end
    end

    context "when the log mixes severities" do
      let(:log_content) { "INFO all good\nfatal: disk failure\nError: boom\n" }

      it "matches ERROR and FATAL case-insensitively and skips other lines" do
        expect(report).to include("fatal: disk failure")
        expect(report).to include("Error: boom")
        expect(report).not_to include("INFO all good")
      end
    end

    context "when the log contains no matching line" do
      let(:log_content) { "INFO nothing to see\nDEBUG still nothing\n" }

      it "prints a none-found marker" do
        expect(report).to include("(none found)")
      end
    end

    context "when the log is larger than the tail window" do
      let(:log_content) do
        "ERROR outside-window\n" \
          "#{"y" * (6 * 1024 * 1024)} ERROR straddling\n" \
          "ERROR inside-window\n"
      end

      it "scans only the tail and discards the partial first line" do
        expect(report).to include("ERROR inside-window")
        expect(report).not_to include("ERROR outside-window")
        expect(report).not_to include("ERROR straddling")
      end
    end
  end

  context "when the log file does not exist" do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Rails.root.join("log", "#{Rails.env}.log")).and_return(false)
    end

    it "prints container log hints instead" do
      expect(report).to include("Log file not found:")
      expect(report).to include("docker logs <container>")
      expect(report).to include("kubectl logs <pod> -n <namespace>")
    end
  end

  context "when logs are written to stdout" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("RAILS_LOG_TO_STDOUT").and_return("true")
    end

    it "points to the container logs instead of scanning a file" do
      expect(report).to include("Logs go to stdout (RAILS_LOG_TO_STDOUT=true)")
      expect(report).to include("docker logs <container>")
      expect(report).to include("kubectl logs <pod> -n <namespace>")
      expect(report).not_to include("ERROR/FATAL lines")
    end
  end

  context "with a database URL containing credentials" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DATABASE_URL").and_return("postgresql://lago:secretpw@db:5432/lago")
    end

    it "prints a Settings subsection with the masked DATABASE_URL" do
      expect(report).to include("## Settings")
      expect(report).to include("postgresql://***@db:5432/lago")
      expect(report).not_to include("secretpw")
    end
  end

  context "when probing Redis" do
    it "silences the Sidekiq logger during the probe and restores its level" do
      original_level = Sidekiq.logger.level
      probed_level = nil
      allow(Sidekiq).to receive(:redis).and_wrap_original do |original, &block|
        probed_level = Sidekiq.logger.level
        original.call(&block)
      end

      report

      expect(probed_level).to eq(Logger::WARN)
      expect(Sidekiq.logger.level).to eq(original_level)
    end
  end

  context "when rendering the Redis settings" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_REDIS_SIDEKIQ_RETRY_WINDOW_SECONDS").and_return(nil)
    end

    it "prints the hardcoded SSL and timeout facts with the retry window default" do
      expect(report).to match(/SSL verify mode\s+: VERIFY_NONE/)
      expect(report).to match(/Connection timeout\s+: 1s/)
      expect(report).to match(/Sidekiq retry window s\s+: 5 \(default\)/)
    end
  end

  context "when Kafka is configured with a security protocol" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return("broker1:9092")
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_SECURITY_PROTOCOL").and_return("SASL_SSL")
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_PASSWORD").and_return("kafkapw")
    end

    it "prints the security protocol and never the password" do
      expect(report).to match(/Security protocol\s+: SASL_SSL/)
      expect(report).not_to include("kafkapw")
    end
  end

  context "when SMTP is configured with authentication" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_SMTP_ADDRESS").and_return("smtp.example.com")
      allow(ENV).to receive(:[]).with("LAGO_SMTP_PORT").and_return("587")
      allow(ENV).to receive(:[]).with("LAGO_SMTP_PASSWORD").and_return("smtppw")
    end

    it "prints the authentication fact and never the password" do
      expect(report).to match(/Authentication\s+: login/)
      expect(report).not_to include("smtppw")
    end
  end

  context "when there are no pending Postgres migrations" do
    let(:context) { instance_double(ActiveRecord::MigrationContext, current_version: 42, pending_migration_versions: []) }

    before do
      allow(ApplicationRecord.connection_pool).to receive(:migration_context).and_return(context)
    end

    it "reports no pending migrations" do
      expect(report).to match(/Pending migrations\s+: none/)
    end
  end

  context "when Postgres migrations are pending" do
    let(:context) do
      instance_double(
        ActiveRecord::MigrationContext,
        current_version: 42,
        pending_migration_versions: [20260101000000, 20260102000000]
      )
    end

    before do
      allow(ApplicationRecord.connection_pool).to receive(:migration_context).and_return(context)
    end

    it "reports the pending migration count and versions" do
      expect(report).to match(/Pending migrations\s+: 2 \(20260101000000, 20260102000000\)/)
    end
  end

  context "when there are no running Sidekiq workers" do
    before do
      allow(Sidekiq::ProcessSet).to receive(:new).and_return([])
    end

    it "prints the no running workers marker" do
      expect(report).to include("## Sidekiq Processes")
      expect(report).to include("(no running workers)")
    end
  end

  context "when a Sidekiq worker is running" do
    let(:process) do
      {
        "hostname" => "worker-1",
        "pid" => 4321,
        "concurrency" => 10,
        "busy" => 3,
        "queues" => %w[default billing],
        "beat" => Time.current.to_f
      }
    end

    before do
      allow(Sidekiq::ProcessSet).to receive(:new).and_return([process])
    end

    it "prints the worker hostname, pid and concurrency" do
      expect(report).to match(/worker-1 pid=4321 concurrency=10 busy=3/)
      expect(report).to include("queues=default,billing")
    end
  end

  context "when the Sidekiq process set cannot be read" do
    before do
      allow(Sidekiq::ProcessSet).to receive(:new).and_raise(StandardError, "process set unavailable")
    end

    it "prints an error marker and still completes the report" do
      expect { report }.not_to raise_error

      expect(report).to include("error: StandardError - process set unavailable")
      expect(report).to include("END OF DIAGNOSTIC")
    end
  end

  context "when rendering the Sidekiq stats" do
    let(:stats) do
      instance_double(
        Sidekiq::Stats,
        processed: 100,
        failed: 2,
        enqueued: 5,
        scheduled_size: 1,
        retry_size: 3,
        dead_size: 4,
        processes_size: 1,
        workers_size: 6
      )
    end

    before do
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)
    end

    it "prints the eight counters" do
      expect(report).to include("## Sidekiq Stats")
      expect(report).to match(/processed: 100/)
      expect(report).to match(/failed: 2/)
      expect(report).to match(/enqueued: 5/)
      expect(report).to match(/scheduled_size: 1/)
      expect(report).to match(/retry_size: 3/)
      expect(report).to match(/dead_size: 4/)
      expect(report).to match(/processes_size: 1/)
      expect(report).to match(/workers_size: 6/)
    end
  end

  context "when an env-backed setting is set to an empty string" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_DATABASE_STATEMENT_TIMEOUT").and_return("")
    end

    it "renders the row as unset instead of blank" do
      expect(report).to match(/Statement timeout\s+: \(unset\)/)
    end
  end
end
