# frozen_string_literal: true

unless defined?(ENHANCED_TASKS)
  ENHANCED_TASKS = %w[db:migrate db:migrate:primary db:rollback db:rollback:primary db:schema:dump:clickhouse].freeze

  ENHANCED_TASKS.each do |task|
    next unless Rake::Task.task_defined?(task)

    Rake::Task[task].enhance do
      Rake::Task['db:clickhouse:filter'].invoke
    end
  end
end

namespace :db do
  desc 'Filter secrets from clickhouse schema file'
  task 'clickhouse:filter' => :environment do
    next unless Rails.env.development?

    migration_file = 'db/clickhouse_schema.rb'
    text = File.read(migration_file)

    text = text.gsub(ENV.fetch('LAGO_KAFKA_BOOTSTRAP_SERVERS', ''), '*****')
    text = text.gsub(ENV.fetch('LAGO_KAFKA_RAW_EVENTS_TOPIC', ''), '*****')
    text = text.gsub(ENV.fetch('LAGO_KAFKA_CLICKHOUSE_CONSUMER_GROUP', ''), '*****')

    File.open(migration_file, 'w') { |file| file.puts text }
  end
end
