# frozen_string_literal: true

module Lago
  # Prints a support diagnostic report for self-hosted deployments.
  #
  # The report is meant to be pasted into support tickets: it only contains
  # versions, configuration (with secrets masked), queue health and row
  # counts, never customer data.
  #
  # @example
  #   Lago::SupportInfo.new.call
  #
  # @example Writing to a custom IO
  #   Lago::SupportInfo.new(output: StringIO.new).call
  class SupportInfo
    SEP = "=" * 72
    LINE = "-" * 72

    SECRET_PATTERN = /
      key|secret|password|passwd|token|dsn|salt|private|credential|
      auth|api_key|access_key|signing|webhook|client_secret|client_id|
      license|master\.key
    /xi

    # Matches URL userinfo credentials (`scheme://user:pass@` or `scheme://user@`).
    # The match is greedy up to the last `@` before the path so passwords
    # containing `@` are fully redacted.
    URL_USERINFO_PATTERN = %r{([a-z][a-z0-9+.-]*://)[^/\s]*@}i

    # Matches sensitive query string parameters (`?password=...`, `&token=...`).
    # The keyword must be a full `_`/`-` separated token of the param name
    # (or the whole name), so `?access_token=` and `?api_key=` are masked
    # while `?monkey=`, `?sslmode=` or `?oauth_state=` are left untouched.
    URL_QUERY_SECRET_PATTERN = /
      ([?&]
      (?:[^=&\s]*[_-])?
      (?:password|passwd|pass|pwd|token|apikey|sslkey|key|secret|signature|sig|auth|credentials|credential|salt|dsn)
      (?:[_-][^=&\s]*)?
      =)
      [^&\s]+
    /xi

    # Extra context appended to integration display names so support readers
    # know which integrations are tax or SSO related.
    INTEGRATION_LABEL_SUFFIXES = {
      "Anrok" => " (tax)",
      "Avalara" => " (tax)",
      "Okta" => " (SSO)"
    }.freeze

    RECENT_ERRORS_LIMIT = 100
    RECENT_ERRORS_PATTERN = /ERROR|FATAL/i
    RECENT_ERRORS_TAIL_BYTES = 5 * 1024 * 1024

    def initialize(output: $stdout)
      @output = output
    end

    def call
      output.puts SEP
      output.puts "  LAGO SUPPORT DIAGNOSTIC"
      output.puts "  Generated : #{Time.current.utc.iso8601}"
      output.puts SEP

      version_and_build
      environment
      configuration
      database
      redis
      clickhouse
      kafka
      smtp
      data_shape
      recent_errors

      output.puts
      output.puts SEP
      output.puts "  END OF DIAGNOSTIC"
      output.puts SEP
    end

    # Masks secrets so the report can be shared in support tickets:
    # - values of secret-looking keys are fully replaced by `***`
    # - URL userinfo credentials are redacted while host/port stay visible
    #   (e.g. `postgresql://lago:pass@db:5432/lago` -> `postgresql://***@db:5432/lago`)
    # - sensitive query string parameters are redacted
    #   (e.g. `?password=secret` -> `?password=***`)
    def mask(key, value)
      if key.to_s.scrub.match?(SECRET_PATTERN)
        "***"
      else
        value.to_s.scrub
          .gsub(URL_USERINFO_PATTERN, '\1***@')
          .gsub(URL_QUERY_SECRET_PATTERN, '\1***')
      end
    end

    private

    attr_reader :output

    # ── helpers ─────────────────────────────────────────────────────────────

    def section(title)
      output.puts
      output.puts LINE
      output.puts "  #{title}"
      output.puts LINE
      yield
    end

    # Returns the block value or a formatted error string, never raises.
    def safe(label = nil)
      yield
    rescue => e
      message = "error: #{e.class} - #{e.message.split("\n").first}"
      label ? "#{label} #{message}" : message
    end

    # Runs a block that prints by itself; if it raises, prints an error line
    # instead so the report keeps going.
    def print_safe(indent = "    ")
      error = safe do
        yield
        nil
      end
      output.puts "#{indent}#{error}" if error
    end

    # ── sections ────────────────────────────────────────────────────────────

    def version_and_build
      section("1. VERSION AND BUILD") do
        version_file = Rails.root.join("LAGO_VERSION")

        version_number = safe { LAGO_VERSION.number }
        # LAGO_VERSION holds either a 40-char git SHA or a version tag string.
        version_content = safe { File.read(version_file).squish }
        commit_sha = if version_content.match?(/\A[0-9a-f]{40}\z/i) || version_content.start_with?("error:")
          version_content
        else
          "(not available, version tag build)"
        end
        build_date = safe { File.ctime(version_file).utc.iso8601 }

        output.puts "  Lago version   : #{version_number}"
        output.puts "  Commit SHA     : #{commit_sha}"
        output.puts "  Build date     : #{build_date}"
      end
    end

    def environment
      section("2. ENVIRONMENT") do
        output.puts "  Ruby           : #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        output.puts "  Rails          : #{Rails.version}"
        output.puts "  Deployment     : #{detect_deployment}"
        output.puts "  Memory limit   : #{detect_memory_limit}"
        output.puts "  CPU quota      : #{detect_cpu_quota}"
      end
    end

    def detect_deployment
      if ENV["KUBERNETES_SERVICE_HOST"].present?
        "kubernetes"
      elsif ENV["LAGO_CLOUD"].present?
        "lago-cloud"
      elsif File.exist?("/.dockerenv")
        "docker/container"
      else
        "unknown"
      end
    end

    def detect_memory_limit
      safe do
        # cgroup v2
        raw = File.read("/sys/fs/cgroup/memory.max").strip
        (raw == "max") ? "unlimited" : "#{(raw.to_i / 1024.0**3).round(2)} GiB"
      rescue Errno::ENOENT
        begin
          # cgroup v1
          bytes = File.read("/sys/fs/cgroup/memory/memory.limit_in_bytes").strip.to_i
          (bytes >= 2**62) ? "unlimited" : "#{(bytes / 1024.0**3).round(2)} GiB"
        rescue Errno::ENOENT
          "unknown"
        end
      end
    end

    def detect_cpu_quota
      safe do
        # cgroup v2
        parts = File.read("/sys/fs/cgroup/cpu.max").strip.split
        (parts[0] == "max") ? "unlimited" : "#{(parts[0].to_f / parts[1].to_f).round(2)} cores"
      rescue Errno::ENOENT
        begin
          # cgroup v1
          quota = File.read("/sys/fs/cgroup/cpu/cpu.cfs_quota_us").strip.to_i
          period = File.read("/sys/fs/cgroup/cpu/cpu.cfs_period_us").strip.to_i
          (quota < 0) ? "unlimited" : "#{(quota.to_f / period).round(2)} cores"
        rescue Errno::ENOENT
          "unknown"
        end
      end
    end

    def configuration
      section("3. CONFIGURATION") do
        output.puts "  ## Environment Variables (secrets redacted)"
        ENV.sort_by { |k, _| k }.each do |key, value|
          print_safe do
            output.puts "    #{key}=#{mask(key, value)}"
          end
        end

        feature_flags_path = Rails.root.join("app/config/feature_flags.yaml")
        if File.exist?(feature_flags_path)
          output.puts
          output.puts "  ## Feature Flags"
          flags = safe { YAML.load_file(feature_flags_path).keys }
          Array(flags).each { |flag| output.puts "    - #{flag}" }
        end

        output.puts
        output.puts "  ## License"
        output.puts "    Premium: #{safe { License.premium? }}"

        output.puts
        output.puts "  ## Payment Providers"
        print_safe do
          payment_provider_rows.each do |name, check|
            output.puts "    #{name.ljust(14)}: #{enabled_label(check)}"
          end
        end

        output.puts
        output.puts "  ## Integrations"
        print_safe do
          integration_rows.each do |name, check|
            output.puts "    #{name.ljust(16)}: #{enabled_label(check)}"
          end
        end
      end
    end

    # Payment providers are derived from the class hierarchy so newly added
    # providers show up in the report without touching this file.
    def payment_provider_rows
      ensure_models_loaded
      PaymentProviders::BaseProvider.descendants
        .map { |klass| [klass.name.demodulize.delete_suffix("Provider"), -> { klass.exists? }] }
        .sort_by(&:first)
    end

    # Integrations are derived from the class hierarchy so newly added
    # integrations show up in the report without touching this file.
    def integration_rows
      ensure_models_loaded
      rows = Integrations::BaseIntegration.descendants.map do |klass|
        name = klass.name.demodulize.delete_suffix("Integration")
        ["#{name}#{INTEGRATION_LABEL_SUFFIXES[name]}", -> { klass.exists? }]
      end

      rows.sort_by(&:first)
    end

    # `descendants` only sees loaded classes; dev and test environments load
    # lazily, so eager loading is forced once before reading the hierarchy.
    def ensure_models_loaded
      @models_loaded ||= begin
        Rails.application.eager_load! unless Rails.application.config.eager_load
        true
      end
    end

    def enabled_label(check)
      safe { check.call ? "enabled" : "disabled" }
    end

    def database
      section("4. DATABASE") do
        pg_version = safe do
          ActiveRecord::Base.connection.select_value("SELECT version()").split(",").first
        end
        db_schema = safe { ApplicationRecord.connection_pool.migration_context.current_version }

        output.puts "  PostgreSQL     : #{pg_version}"
        output.puts "  DB schema ver  : #{db_schema}"

        output.puts
        output.puts "  ## DB Connection Pool"
        print_safe do
          ActiveRecord::Base.connection_pool.stat.each do |key, value|
            output.puts "    #{key}: #{value}"
          end
        end
      end
    end

    def redis
      section("5. REDIS") do
        redis_version = safe do
          Sidekiq.redis do |c|
            c.call("INFO", "server").match(/redis_version:([^\r\n]+)/)&.captures&.first&.strip
          end
        end

        output.puts "  Redis          : #{redis_version}"

        output.puts
        output.puts "  ## Redis Memory"
        print_safe do
          Sidekiq.redis do |c|
            info = c.call("INFO", "memory")
            %w[used_memory_human used_memory_peak_human maxmemory_human].each do |key|
              value = info.match(/#{key}:([^\r\n]+)/)&.captures&.first&.strip
              output.puts "    #{key}: #{value}" if value
            end
          end
        end

        output.puts
        output.puts "  ## Sidekiq Queues"
        print_safe do
          Sidekiq::Queue.all.sort_by(&:name).each do |q|
            output.puts format("    %-22s size=%-8d latency=%.2fs", q.name, q.size, q.latency)
          end
        end

        output.puts
        output.puts "  Retry set size : #{safe { Sidekiq::RetrySet.new.size }}"
        output.puts "  Dead set size  : #{safe { Sidekiq::DeadSet.new.size }}"

        output.puts
        output.puts "  ## Dead Set - last 50 entries (class + error class only)"
        print_safe do
          entries = dead_set_entries.first(50)
          if entries.empty?
            output.puts "    (empty)"
          else
            entries.each do |job|
              ts = safe { Time.zone.at(job["failed_at"].to_f).utc.iso8601 }
              output.puts "    #{ts}  #{job_class(job)}  [#{job["error_class"]}]"
            end
          end
        end
      end
    end

    def clickhouse
      section("6. CLICKHOUSE") do
        enabled = ENV["LAGO_CLICKHOUSE_ENABLED"].present?

        output.puts "  Enabled        : #{enabled}"
        if enabled
          version = safe { Clickhouse::BaseRecord.connection.select_value("SELECT version()") }
          output.puts "  Version        : #{version}"
        end
      end
    end

    def kafka
      section("7. KAFKA") do
        enabled = ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].present?

        output.puts "  Enabled        : #{enabled}"
        if enabled
          servers = mask("LAGO_KAFKA_BOOTSTRAP_SERVERS", ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"])
          output.puts "  Bootstrap servers : #{servers}"
        end
      end
    end

    def smtp
      section("8. SMTP") do
        enabled = ENV["LAGO_SMTP_ADDRESS"].present?

        output.puts "  Enabled        : #{enabled}"
        if enabled
          output.puts "  Address        : #{ENV["LAGO_SMTP_ADDRESS"]}"
          output.puts "  Port           : #{ENV["LAGO_SMTP_PORT"]}"
        end
      end
    end

    def data_shape
      section("9. DATA SHAPE (counts only, no content)") do
        output.puts "  ## Key Table Row Counts (estimated)"
        {
          "Organizations" => -> { estimated_count(Organization) },
          "Customers" => -> { estimated_count(Customer) },
          "Subscriptions" => -> { estimated_count(Subscription) },
          "Invoices" => -> { estimated_count(Invoice) },
          "Fees" => -> { estimated_count(Fee) },
          "Charges" => -> { estimated_count(Charge) },
          # ::Event is required: the lago-expression gem defines Lago::Event,
          # which shadows the model inside this namespace.
          "Events" => -> { estimated_count(::Event) }
        }.each do |label, count_proc|
          output.puts format("    %-16s: %s", label, safe { count_proc.call })
        end

        output.puts
        output.puts "  ## Ingestion / Generation Rates"
        output.puts "    Events   last 24h : #{safe { count_with_timeout { ::Event.where(created_at: 24.hours.ago..).count } }}"
        output.puts "    Invoices last 7d  : #{safe { count_with_timeout { Invoice.where(created_at: 7.days.ago..).count } }}"

        output.puts
        output.puts "  ## Failed Jobs by Class - Sidekiq dead set, last 24h"
        print_safe do
          cutoff = 24.hours.ago.to_f
          by_class = dead_set_entries
            .select { |j| j["failed_at"].to_f >= cutoff }
            .group_by { |j| job_class(j) }
            .transform_values(&:count)
            .sort_by { |_, count| -count }

          if by_class.empty?
            output.puts "    (none)"
          else
            by_class.each { |klass, count| output.puts format("    %-52s %d", klass, count) }
          end
        end
      end
    end

    # Reads the dead set once for both the last-50 listing and the 24h tally.
    # Each caller stays wrapped in safe/print_safe so a Redis failure prints
    # an error marker instead of crashing the report.
    def dead_set_entries
      @dead_set_entries ||= Sidekiq::DeadSet.new.to_a
    end

    # ActiveJob jobs are enqueued through a Sidekiq wrapper, so the raw
    # "class" is always ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.
    # The real job class lives in the "wrapped" key.
    def job_class(job)
      job["wrapped"] || job["class"]
    end

    # Uses the PostgreSQL planner estimate to avoid a full table scan on
    # large production tables. Falls back to an exact count, bounded by a
    # statement timeout, when the table was never analyzed (negative reltuples).
    def estimated_count(model)
      estimate = ActiveRecord::Base.connection.select_value(
        "SELECT reltuples::bigint FROM pg_class WHERE oid = '#{model.table_name}'::regclass"
      ).to_i

      estimate.negative? ? count_with_timeout { model.count } : estimate
    end

    # Runs a range-count query with a local statement timeout so a missing
    # index cannot stall the whole report.
    def count_with_timeout
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '15s'")
        yield
      end
    end

    def recent_errors
      section("10. RECENT ERRORS") do
        log_path = Rails.root.join("log", "#{Rails.env}.log")

        if File.exist?(log_path)
          output.puts "  ## Last #{RECENT_ERRORS_LIMIT} ERROR/FATAL lines (last 5 MB of #{log_path})"
          print_safe do
            lines = last_matching_lines(log_path, RECENT_ERRORS_PATTERN, RECENT_ERRORS_LIMIT)
            if lines.empty?
              output.puts "    (none found)"
            else
              lines.each { |line| output.puts line }
            end
          end
        else
          output.puts "  Log file not found: #{log_path}"
          output.puts "  In containerized deployments check stdout via:"
          output.puts "    docker logs <container>"
          output.puts "    kubectl logs <pod> -n <namespace>"
        end
      end
    end

    # Scans only the last RECENT_ERRORS_TAIL_BYTES of the file, keeping the
    # last `limit` lines matching `pattern` in a bounded buffer, so huge log
    # files are never read in full.
    def last_matching_lines(path, pattern, limit)
      buffer = []
      File.open(path) do |file|
        seek_pos = [file.size - RECENT_ERRORS_TAIL_BYTES, 0].max
        file.seek(seek_pos)
        # Discard the first, possibly partial, line when starting mid-file.
        file.gets if seek_pos.positive?

        file.each_line do |line|
          clean = line.scrub
          next unless clean.match?(pattern)

          buffer << clean.chomp
          buffer.shift if buffer.size > limit
        end
      end
      buffer
    end
  end
end
