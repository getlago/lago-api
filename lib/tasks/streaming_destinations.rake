# frozen_string_literal: true

# rubocop:disable Rails/Output
namespace :streaming_destinations do
  desc "Send one customer's current usage to their destination, and report what went out"
  task :verify, [:organization_id] => :environment do |_task, args|
    Rails.logger.level = Logger::INFO

    organization = Organization.find(args.fetch(:organization_id))
    event_type = EventDestinations::CustomerUsage::RefreshedService::EVENT_TYPE
    destination = StreamingDestinations::KinesisDestination.for_event(organization, event_type).first

    abort("No destination on #{organization.name} for #{event_type}") if destination.nil?

    puts ""
    puts "----- destination -----"
    puts "organization : #{organization.name} (#{organization.id})"
    puts "stream       : #{destination.stream_arn}"
    puts "region       : #{destination.region}"
    puts "role         : #{destination.role_arn}"
    puts "events       : #{destination.event_types.join(", ")}"
    puts ""
    puts "Confirm the account id in the stream ARN belongs to the environment above before"
    puts "continuing. Production and development are separate organizations on this database."
    puts ""
    print "Customer external id to deliver: "
    external_id = $stdin.gets.to_s.strip
    abort("No customer given") if external_id.empty?

    customer = organization.customers.find_by!(external_id:)
    subscriptions = customer.active_subscriptions.count
    abort("#{external_id} has no active subscription, so nothing would be delivered") if subscriptions.zero?

    puts ""
    puts "Delivering #{subscriptions} record(s) for #{external_id}. Watch for outcome=delivered."
    puts ""

    EventDestinations::CustomerUsage::RefreshedService.call(object: customer)

    puts ""
    puts "Done. A line with outcome=delivered and a shard and sequence number means the record"
    puts "landed. outcome=dropped means it did not: read the error field."
    puts "Failure modes: docs/streaming_delivery_monitoring.md"
  end

  desc "Enqueue a burst of deliveries to size the streaming worker and the stream's shards"
  task :burst, [:organization_id, :count] => :environment do |_task, args|
    Rails.logger.level = Logger::INFO

    organization = Organization.find(args.fetch(:organization_id))
    count = Integer(args.fetch(:count, 1_000))
    event_type = EventDestinations::CustomerUsage::RefreshedService::EVENT_TYPE

    abort("No destination for #{event_type}") unless
      StreamingDestinations::KinesisDestination.for_event(organization, event_type).exists?

    customers = organization.customers
      .where(id: organization.subscriptions.active.select(:customer_id))
      .limit(count)
      .to_a

    abort("No customer with an active subscription on #{organization.name}") if customers.empty?

    puts ""
    puts "Enqueueing #{customers.size} deliveries on the streaming queue."
    puts "This is the push load the design has no numbers for. Measure, over the run:"
    puts "  * queue latency and depth on `streaming`, from the Sidekiq Pro metrics"
    puts "  * duration_ms on outcome=delivered lines, for end-to-end freshness"
    puts "  * bytes on the same lines, for p50/p95/max payload size"
    puts "  * the ratio of outcome=superseded to outcome=delivered"
    puts "  * AssumeRole call count in CloudTrail, filtered on session name"
    puts "    #{EventDestinations::KinesisProducer::ROLE_SESSION_NAME}: it should be roughly one"
    puts "    per process per hour, not one per delivery"
    puts ""

    started_at = Time.current
    customers.each { DeliverEventJob.perform_later(event_type, it) }

    puts "Enqueued in #{(Time.current - started_at).round(2)}s."
    puts "Shard sizing: records per burst against 1,000 records/s per shard."
  end
end
# rubocop:enable Rails/Output
