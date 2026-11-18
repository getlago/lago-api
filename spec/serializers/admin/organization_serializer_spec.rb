# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::OrganizationSerializer do
  subject(:serialized) { described_class.new(organization).serialize }

  let(:production) do
    create(:organization, :self_serve, :with_sandbox, name: "Hooli", document_numbering: "per_customer",
      premium_integrations: [])
  end
  let(:sandbox) { production.sandbox_organization }

  before { travel_to(Time.zone.parse("2026-11-01T10:00:00Z")) }

  context "with a production organization" do
    let(:organization) { production }

    it "serializes it with its sandbox" do
      expect(serialized).to eq(
        id: production.id,
        name: "Hooli",
        document_numbering: "per_customer",
        premium_integrations: [],
        self_serve: true,
        environment: "production",
        production_organization_id: nil,
        sandbox_organization_id: sandbox.id,
        created_at: "2026-11-01T10:00:00Z",
        updated_at: "2026-11-01T10:00:00Z"
      )
    end
  end

  context "with a sandbox" do
    let(:organization) { Organization.find(sandbox.id) }

    before { allow(organization).to receive(:sandbox_organization).and_call_original }

    it "serializes it with its production, without looking up a sandbox" do
      expect(serialized).to eq(
        id: sandbox.id,
        name: "Hooli Sandbox",
        document_numbering: "per_customer",
        premium_integrations: [],
        self_serve: true,
        environment: "sandbox",
        production_organization_id: production.id,
        sandbox_organization_id: nil,
        created_at: "2026-11-01T10:00:00Z",
        updated_at: "2026-11-01T10:00:00Z"
      )
      expect(organization).not_to have_received(:sandbox_organization)
    end
  end
end
