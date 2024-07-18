# frozen_string_literal: true

require 'net/http'
require 'yaml'

namespace :upgrade do
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
    versions = versions_data['versions']
    current_version_data = versions.find do |version_data|
      Gem::Version.new(version_data['version']) == Gem::Version.new(current_version)
    end

    if current_version_data.nil?
      puts "Current version #{current_version} not found in versions data."
      return true
    end

    migrations = current_version_data['migrations']
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
      Gem::Version.new(versions['versions'].last['version'])
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
    versions = versions_data['versions']
    latest_version = Gem::Version.new(versions.last['version'])

    if current_version >= latest_version
      puts "Your system is already up-to-date with version #{latest_version}."
      return
    end

    puts "Your current version is #{current_version}. The latest version is #{latest_version}."

    migration_path = []

    versions.each do |version_data|
      version = Gem::Version.new(version_data['version'])
      next if version <= current_version

      migrations = version_data['migrations']
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
    ActiveRecord::Base.connection.table_exists?('schema_migrations') &&
      ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations").include?(migration.to_s)
  end

  def background_jobs_cleared?
    queue = Sidekiq::Queue.new('background_migration')
    queue.size == 0
  end
end
