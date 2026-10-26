# frozen_string_literal: true

# rubocop:disable Rails/Output,Rails/Exit
module TaskPrompt
  def self.ask(prompt)
    print prompt
    $stdin.gets.chomp
  end

  def self.confirm!(prompt)
    abort "Aborted." unless ask(prompt).downcase == "y"
  end

  def self.confirm?(prompt)
    ask(prompt).downcase == "y"
  end

  def self.ask_for_organization
    organization_id = ask("Organization ID: ")
    organization = Organization.find_by(id: organization_id)
    abort "Organization not found with ID: #{organization_id}" unless organization

    puts "Organization found: #{organization.name} (#{organization.id})"
    confirm!("Is this the correct organization? (y/n): ")

    organization
  end

  def self.ask_for_subscription_ids
    input = ask("Subscription IDs to refill (comma or space separated, leave blank to fill a whole organization): ")
    input.split(/[\s,]+/).reject(&:empty?)
  end

  # The listed subscriptions of the organization, or a random sample of its active ones
  def self.ask_for_sampled_subscriptions(organization)
    subscription_ids = ask_for_subscription_ids
    if subscription_ids.any?
      subscriptions = Subscription.where(organization_id: organization.id, id: subscription_ids).to_a
      missing_ids = subscription_ids - subscriptions.map(&:id)
      puts "Not found in the organization, skipped: #{missing_ids.join(", ")}" if missing_ids.any?

      return subscriptions
    end

    active_count = Subscription.active.where(organization_id: organization.id).count
    puts "Organization has #{active_count} active subscription(s)."
    sample_size = ask("Number of active subscriptions to sample [50]: ")
    sample_size = sample_size.empty? ? 50 : Integer(sample_size, exception: false)
    abort "Invalid sample size: expected a positive integer." unless sample_size&.positive?

    Subscription.active
      .where(organization_id: organization.id)
      .order(Arel.sql("RANDOM()"))
      .limit(sample_size)
      .to_a
  end

  def self.ask_for_timestamp_range
    from_time = ask_for_timestamp("From timestamp (UTC, e.g. 2026-01-01 00:00:00): ")
    to_time = ask_for_timestamp("To timestamp (UTC, e.g. 2026-01-31 23:59:59): ")

    abort "from_timestamp must be before to_timestamp" if from_time > to_time

    [from_time, to_time]
  end

  def self.ask_for_timestamp(prompt)
    input = ask(prompt)
    timestamp = Time.zone.parse(input)
    abort "Invalid timestamp: #{input}" unless timestamp

    timestamp
  end

  def self.ask_for_date(prompt, default:)
    input = ask("#{prompt} [#{default}]: ")
    return default if input.empty?

    date = begin
      Date.parse(input)
    rescue ArgumentError
      nil
    end
    abort "Invalid date: #{input}" unless date

    date
  end
end
# rubocop:enable Rails/Output,Rails/Exit
