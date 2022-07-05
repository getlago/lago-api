# frozen_string_literal: true

module Trackable
  extend ActiveSupport::Concern

  included do
    before_action :set_current_context
  end

  private

  def set_current_context
    CurrentContext.organization_id = current_user.memberships.first&.organization_id
    CurrentContext.membership_id = current_user.memberships.first&.id
  end
end
