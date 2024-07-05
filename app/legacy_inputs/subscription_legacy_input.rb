# frozen_string_literal: true

class SubscriptionLegacyInput < BaseLegacyInput
  def create_input
    if args[:subscription_date].present?
      args[:subscription_at] ||= date_in_organization_timezone(args[:subscription_date], end_of_day: false)
    end

    args
  end
  alias_method :update_input, :create_input
end
