# frozen_string_literal: true

class WalletLegacyInput < BaseLegacyInput
  def create_input
    if args[:expiration_date].present?
      args[:expiration_at] ||= date_in_organization_timezone(args[:expiration_date], end_of_day: true)
    end

    args
  end
  alias_method :update_input, :create_input
end
