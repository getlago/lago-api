# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ExternalIds do
  let(:registration) { create(:agent_registration) }

  describe ".customer and .subscription" do
    it "name the agent's customer and subscription after its registration" do
      expect(described_class.customer(registration)).to eq("agent_#{registration.id}")
      expect(described_class.subscription(registration)).to eq("agent_#{registration.id}")
    end
  end

  describe ".of" do
    it "names the same ids in SQL, for a lookup over a storefront's registrations" do
      other = create(:agent_registration, storefront: registration.storefront)
      elsewhere = create(:agent_registration)
      [registration, other, elsewhere].each { create(:customer, organization: it.organization, external_id: described_class.customer(it)) }

      found = Customer.where(external_id: described_class.of(registration.storefront.agent_registrations))

      expect(found.map(&:external_id)).to match_array(["agent_#{registration.id}", "agent_#{other.id}"])
    end
  end
end
