# frozen_string_literal: true

require_relative "../task_prompt"

# rubocop:disable Rails/Output,Rails/Exit
namespace :receipes do
  namespace :events do
    desc "Soft-delete PG events for an organization within a time range"
    task delete: :environment do
      organization = TaskPrompt.ask_for_organization
      abort "This task only supports organizations using PostgreSQL events store." unless organization.postgres_events_store?

      from_time, to_time = TaskPrompt.ask_for_timestamp_range

      events = Event.where(organization_id: organization.id)
        .from_datetime(from_time)
        .to_datetime(to_time)

      count = events.count

      if count.zero?
        puts "No events found in the given time range. Nothing to delete."
        next
      end

      puts "\nThis will soft-delete #{count} events from \"#{organization.name}\" " \
        "from #{from_time.utc} to #{to_time.utc} (inclusive)."
      TaskPrompt.confirm!("Continue? (y/n): ")

      events.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      puts "Done. #{count} events soft-deleted."
    end
  end
end
# rubocop:enable Rails/Output,Rails/Exit
