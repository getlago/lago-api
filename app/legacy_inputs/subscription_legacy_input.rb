# frozen_string_literal: true

class SubscriptionLegacyInput < BaseLegacyInput
  def create_input
    if args[:subscription_date].present?
      args[:subscription_at] ||= date_in_organization_timezone(args[:subscription_date], end_of_day: false)
    end

    return args if args[:plan_overrides].blank?

    args[:plan_overrides] = PlanLegacyInput.new(organization, args[:plan_overrides]).create_input
    args
  end
  alias update_input create_input
end
