class SegmentIdentifyJob < ApplicationJob
  queue_as :default

  def perform(membership_id:)
    return if ENV['LAGO_DISABLE_SEGMENT'] == 'true'
    return if membership_id.nil? || membership_id == 'membership/unidentifiable'

    membership = Membership.find(membership_id.sub(/\Amembership\//, ''))
    traits = { created_at: membership.created_at, hosting_type: hosting_type, version: version }
    traits.merge!(email: membership.user.email) if hosting_type == 'cloud'

    SEGMENT_CLIENT.identify(user_id: membership_id, traits: traits)
  end

  private

  def hosting_type
    @hosting_type ||= ENV['LAGO_CLOUD'] == 'true' ? 'cloud' : 'self'
  end

  def version
    Utils::VersionService.new.version.version.number
  end
end
