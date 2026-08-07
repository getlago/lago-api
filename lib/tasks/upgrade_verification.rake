# frozen_string_literal: true

require "net/http"
require "yaml"

namespace :upgrade do
  # Note: this task is to be filled with jobs needed to be run before the upgrade
  #       and is to be changed depending on what is required for the next version.
  desc "Performs required jobs that need to be run after the upgrade"
  task perform_required_jobs: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    resources_to_fill = [
      # TODO: Uncomment when code is required for wallets
      # {model: Wallet, job: DatabaseMigrations::PopulateWalletsWithCodeJob},
    ]

    puts "##################################\nStarting required jobs"
    puts "\n#### Checking for resource to fill ####"

    to_fill = []

    resources_to_fill.each do |resource|
      model = resource[:model]
      pp "- Checking #{model.name}: 🔎"
      count = model.where(code: nil).count

      if count > 0
        to_fill << resource
        pp "  -> #{count} records to fill 🧮"
      else
        pp "  -> Nothing to do ✅"
      end
    end

    if to_fill.any?
      puts "\n#### Enqueue jobs in the low_priority queue ####"
      to_fill.each do |resource|
        pp "- Enqueuing #{resource[:job].name}"
        resource[:job].perform_later
      end
    end

    while to_fill.present?
      sleep 5
      puts "\n#### Checking status ####"

      to_delete = []
      to_fill.each do |resource|
        model = resource[:model]
        pp "- Checking #{model.name}: 🔎"
        count = model.where(code: nil).count

        if count > 0
          pp "  -> #{count} remaining 🧮"
        else
          to_delete << resource
          pp "  -> Done ✅"
        end
      end
      to_delete.each { to_fill.delete(it) }
    end

    [
      ["plan charges", DatabaseMigrations::EnqueueChargeFilterCodeBackfillService, DatabaseMigrations::BackfillChargeFilterCodesJob, :parents],
      ["their overrides", DatabaseMigrations::EnqueueChildChargeFilterCodeBackfillService, DatabaseMigrations::BackfillChildChargeFilterCodesJob, :children]
    ].each do |label, enqueue, job, pass|
      puts "\n#### Backfilling charge filter codes on #{label} ####"

      enqueue.call

      # Sidekiq answers cheaply but not exactly: busy workers are reported from a heartbeat that
      # refreshes every few seconds, so right after the queue drains there is a window where the
      # jobs are running and nothing shows it. It is the trigger, not the verdict — the count
      # below is, and it is only reached once the queue looks quiet.
      loop do
        sleep 5

        if backfill_jobs_running?(job)
          pp "- Checking #{job.name}: 🔎"
          pp "  -> #{Sidekiq::Queue.new(job.queue_name).size} jobs left 🧮"
          next
        end

        remaining = codeless_filters_that_can_be_filled(pass)
        break if remaining.zero?

        pp "- Checking #{job.name}: 🔎"
        pp "  -> #{remaining} filters still fillable 🧮"
      end

      pp "  -> Done ✅"
    end

    puts "\n#### All good, ready to Upgrade! ✅ ####"
  end

  desc "Verifies the current system's readiness for an upgrade and outlines necessary migration paths"
  task verify: [:check_migrations, :check_background_jobs] do
    current_version = fetch_current_version
    versions_data = load_versions_data
    verify_upgrade_path(current_version, versions_data)
  end

  desc "Checks if all migrations for the current version have been run and if the system is ready to upgrade"
  task check_migrations: :environment do
    current_version = fetch_current_version
    versions_data = load_versions_data
    ready_to_upgrade = check_migrations_status(current_version, versions_data)
    unless ready_to_upgrade
      puts "System is not ready to upgrade. Please ensure all migrations for the current version have been run."
      exit 1
    end
  end

  desc "Checks if all jobs on the 'background_migration' queue have been run"
  task check_background_jobs: :environment do
    unless background_jobs_cleared?
      puts "System is not ready to upgrade. There are pending jobs in the 'background_migration' queue."
      exit 1
    end
  end

  private

  def check_migrations_status(current_version, versions_data)
    versions = versions_data["versions"]
    current_version_data = versions.find do |version_data|
      Gem::Version.new(version_data["version"]) == Gem::Version.new(current_version)
    end

    if current_version_data.nil?
      puts "Current version #{current_version} not found in versions data."
      return true
    end

    migrations = current_version_data["migrations"]
    if migrations.empty?
      puts "No migrations required for current version #{current_version}. System is ready to upgrade."
      return true
    end

    missing_migrations = migrations.reject { |migration| migration_already_run?(migration) }

    if missing_migrations.empty?
      puts "All migrations for version #{current_version} have been run. System is ready to upgrade."
      true
    else
      puts "The following migrations for version #{current_version} have not been run:"
      missing_migrations.each { |migration| puts "  - #{migration}" }
      false
    end
  end

  def fetch_current_version
    if Rails.env.development?
      # Load the version from versions.yml file in development
      versions = YAML.load_file(Rails.root.join("config/versions.yml"))
      Gem::Version.new(versions["versions"].last["version"])
    else
      # Use the LAGO_VERSION constant in other environments
      Gem::Version.new(LAGO_VERSION.number)
    end
  end

  def load_versions_data
    uri = URI("https://raw.githubusercontent.com/getlago/lago-api/main/config/versions.yml")
    response = Net::HTTP.get(uri)
    YAML.load(response)
  end

  def verify_upgrade_path(current_version, versions_data)
    versions = versions_data["versions"]
    latest_version = Gem::Version.new(versions.last["version"])

    if current_version >= latest_version
      puts "Your system is already up-to-date with version #{latest_version}."
      return
    end

    puts "Your current version is #{current_version}. The latest version is #{latest_version}."

    migration_path = []

    versions.each do |version_data|
      version = Gem::Version.new(version_data["version"])
      next if version <= current_version

      migrations = version_data["migrations"]
      unless migrations.empty?
        migration_path << {version: version, migrations: migrations}
      end
    end

    if migration_path.empty?
      puts "You can upgrade to the latest version #{latest_version}."
    else
      puts "You need to upgrade. Here is the migration path:"
      migration_path.each do |upgrade|
        puts "To upgrade to version #{upgrade[:version]}, you need to run the following migrations:"
        upgrade[:migrations].each do |migration|
          puts "  - #{migration}"
        end
      end
    end
  end

  def migration_already_run?(migration)
    ActiveRecord::Base.connection.table_exists?("schema_migrations") &&
      ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations").include?(migration.to_s)
  end

  def background_jobs_cleared?
    queue = Sidekiq::Queue.new("background_migration")
    queue.size == 0
  end

  # Sidekiq stores ActiveJob entries under the adapter's wrapper class, so `klass` reads
  # "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" and never matches a job name. The
  # job's own name lives in `wrapped`, which `display_class` reads back off a queue entry.
  # How many filters are still waiting for a code that the pass can actually give them. It reaches
  # zero, which a plain `code IS NULL` count never does: a charge holding two filters on one
  # predicate keeps theirs on purpose, and so does an override that lost the filter it was copied
  # from. Those are excluded here, which is what makes this an end condition.
  #
  # It aggregates predicates, so it is not cheap — a minute and a half over every plan charge on
  # the largest deployment. That is why it only runs once the queue has gone quiet: by then the
  # scope is whatever is left rather than everything.
  def codeless_filters_that_can_be_filled(pass)
    sql = (pass == :parents) ? parent_pending_codes_sql : child_pending_codes_sql

    ActiveRecord::Base.connection.select_value(sql).to_i
  end

  # A plan's filter can be filled unless another filter on the same charge holds the same predicate
  def parent_pending_codes_sql
    <<~SQL.squish
      WITH pending AS (
        SELECT DISTINCT cf.charge_id
        FROM charge_filters cf
        JOIN charges ch ON ch.id = cf.charge_id
        JOIN plans pl ON pl.id = ch.plan_id
        WHERE cf.code IS NULL AND cf.deleted_at IS NULL
          AND ch.parent_id IS NULL AND ch.deleted_at IS NULL
          AND pl.parent_id IS NULL AND pl.deleted_at IS NULL
      ),
      predicates AS (
        #{filter_predicates_sql("JOIN pending p ON p.charge_id = cf.charge_id")}
      )
      SELECT count(*)
      FROM (SELECT *, count(*) OVER (PARTITION BY charge_id, predicate) AS siblings FROM predicates) x
      WHERE code IS NULL AND siblings = 1
    SQL
  end

  # An override's filter can be filled when its parent holds that predicate exactly once, with a
  # code. Anything else is either orphaned or a decision the parent could not make either.
  def child_pending_codes_sql
    <<~SQL.squish
      WITH pending AS (
        SELECT DISTINCT cf.charge_id, ch.parent_id
        FROM charge_filters cf
        JOIN charges ch ON ch.id = cf.charge_id
        WHERE cf.code IS NULL AND cf.deleted_at IS NULL
          AND ch.parent_id IS NOT NULL AND ch.deleted_at IS NULL
      ),
      predicates AS (
        #{filter_predicates_sql("JOIN pending p ON p.charge_id = cf.charge_id OR p.parent_id = cf.charge_id")}
      ),
      inheritable AS (
        SELECT charge_id, predicate, min(code) AS code
        FROM predicates
        GROUP BY charge_id, predicate
        HAVING count(*) = 1 AND min(code) IS NOT NULL
      )
      SELECT count(*)
      FROM predicates f
      JOIN pending p ON p.charge_id = f.charge_id
      JOIN inheritable i ON i.charge_id = p.parent_id AND i.predicate = f.predicate
      WHERE f.code IS NULL
    SQL
  end

  # Built the same way as ChargeFilter.generate_code reads the values: keys sorted, and the values
  # sorted within each key. Without both, the same predicate compares as two different ones.
  def filter_predicates_sql(join)
    <<~SQL.squish
      SELECT cf.id, cf.charge_id, cf.code,
             string_agg(
               bmf.key || ':' || (SELECT string_agg(v, '+' ORDER BY v) FROM unnest(cfv.values) AS v),
               '|' ORDER BY bmf.key
             ) AS predicate
      FROM charge_filters cf
      #{join}
      JOIN charge_filter_values cfv ON cfv.charge_filter_id = cf.id AND cfv.deleted_at IS NULL
      JOIN billable_metric_filters bmf ON bmf.id = cfv.billable_metric_filter_id
      WHERE cf.deleted_at IS NULL
      GROUP BY cf.id, cf.charge_id, cf.code
    SQL
  end

  def backfill_jobs_running?(job_class)
    return true if Sidekiq::Queue.new(job_class.queue_name).any? { |job| job.display_class == job_class.name }
    return true if Sidekiq::ScheduledSet.new.any? { |job| job.display_class == job_class.name }

    Sidekiq::Workers.new.any? do |_process_id, _thread_id, work|
      work.dig("payload", "wrapped") == job_class.name
    end
  end
end
