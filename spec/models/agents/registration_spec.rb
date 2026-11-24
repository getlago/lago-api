# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Registration do
  subject(:registration) { build(:agent_registration) }

  describe "enums" do
    it do
      expect(registration).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(active: "active", revoked: "revoked")
    end
  end

  describe "associations" do
    it do
      expect(registration).to belong_to(:organization)
      expect(registration).to belong_to(:storefront)
        .class_name("Integrations::AgentStorefrontIntegration")
        .with_foreign_key(:integration_id)
    end
  end

  describe "validations" do
    it do
      expect(registration).to validate_presence_of(:key_id)
      expect(registration).to validate_presence_of(:public_key)
      expect(registration).to have_readonly_attribute(:key_id)
      expect(registration).to have_readonly_attribute(:public_key)
    end
  end
end
