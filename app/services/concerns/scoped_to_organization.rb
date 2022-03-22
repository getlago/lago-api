# frozen_string_literal: true

module ScopedToOrganization
  extend ActiveSupport::Concern

  def organization_member?(organization_id)
    return false unless result.user
    return false unless organization_id

    result.user.organizations.exists?(id: organization_id)
  end
end
