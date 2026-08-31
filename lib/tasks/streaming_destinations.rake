# frozen_string_literal: true

namespace :streaming_destinations do
  # Stands in for the CRUD API during the POC: streaming destinations are seeded
  # by an operator, not managed by the customer.
  #
  # Every value can come from a task argument or the matching ENV variable, the
  # argument winning. Idempotent on (organization_id, code), so re-running with
  # new settings updates the existing destination in place.
  #
  #   bundle exec rake "streaming_destinations:upsert_kinesis[<org_id>,<code>]" \
  #     STREAM_ARN=arn:aws:kinesis:eu-west-1:111122223333:stream/lago \
  #     REGION=eu-west-1 \
  #     ROLE_ARN=arn:aws:iam::111122223333:role/LagoStreamingWriter \
  #     EXTERNAL_ID=some-shared-secret \
  #     EVENT_TYPES=subscription.updated,wallet.updated
  #
  # EVENT_TYPES is optional; omit it to subscribe the destination to every event
  # type. Pass EVENT_TYPES="*" to reset an existing destination back to all.
  desc "Create or update a Kinesis streaming destination for an organization"
  task :upsert_kinesis, [:organization_id, :code] => :environment do |_task, args|
    organization_id = args[:organization_id].presence || ENV["ORGANIZATION_ID"].presence
    code = args[:code].presence || ENV["CODE"].presence || "kinesis"

    raise "organization_id is required" if organization_id.nil?

    organization = Organization.find(organization_id)

    stream_arn = ENV["STREAM_ARN"].presence
    region = ENV["REGION"].presence
    role_arn = ENV["ROLE_ARN"].presence
    external_id = ENV["EXTERNAL_ID"].presence

    event_types =
      if ENV["EVENT_TYPES"].blank?
        nil
      elsif ENV["EVENT_TYPES"] == "*"
        :all
      else
        ENV["EVENT_TYPES"].split(",").map(&:strip).reject(&:blank?)
      end

    destination = StreamingDestinations::KinesisDestination.find_or_initialize_by(
      organization: organization,
      code: code
    )
    created = destination.new_record?

    destination.name = ENV["NAME"].presence || destination.name || "Kinesis (#{code})"

    # Only overwrite what was actually supplied, so a partial re-run does not
    # blank out settings that are already correct.
    destination.stream_arn = stream_arn if stream_arn
    destination.region = region if region
    destination.role_arn = role_arn if role_arn
    destination.external_id = external_id if external_id
    unless event_types.nil?
      destination.event_types = (event_types == :all) ? nil : event_types
    end

    destination.save!

    puts "#{created ? "Created" : "Updated"} #{destination.type} #{destination.id}"
    puts "  organization: #{organization.name} (#{organization.id})"
    puts "  code:         #{destination.code}"
    puts "  stream_arn:   #{destination.stream_arn}"
    puts "  region:       #{destination.region}"
    puts "  role_arn:     #{destination.role_arn}"
    puts "  external_id:  #{destination.external_id.present? ? "(set)" : "(none)"}"
    puts "  event_types:  #{destination.event_types || "(all)"}"
  end
end
