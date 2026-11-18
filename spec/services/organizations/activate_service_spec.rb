# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::ActivateService do
  subject(:result) { described_class.call(organization:) }

  let(:organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }

  before { allow(ApiKeys::CacheService).to receive(:expire_all_cache) }

  it "opens the organization and clears its API key cache" do
    expect(result).to be_success
    expect(result.organization).to eq(organization)
    expect(organization.reload.activation_status).to eq("active")
    expect(ApiKeys::CacheService).to have_received(:expire_all_cache).with(organization).once
  end

  it "reads the organization again under the lock, so a stale copy is not activated twice" do
    stale = Organization.find(organization.id)
    organization.update!(activation_status: "active")

    expect(described_class.call(organization: stale)).to be_success
    expect(ApiKeys::CacheService).not_to have_received(:expire_all_cache)
  end

  context "with an active organization" do
    let(:organization) { create(:organization, :self_serve) }

    it "succeeds without changing anything" do
      expect { result }.not_to change { organization.reload.updated_at }

      expect(result).to be_success
      expect(organization.reload.activation_status).to eq("active")
      expect(ApiKeys::CacheService).not_to have_received(:expire_all_cache)
    end
  end

  context "with an organization that is not self-serve" do
    let(:organization) { create(:organization) }

    it "refuses" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("organization_not_self_serve_production")
    end
  end

  context "with a sandbox" do
    let(:organization) do
      create(:organization, :self_serve, :sandbox, production_organization: create(:organization, :self_serve))
    end

    it "refuses" do
      expect(result).to be_failure
      expect(result.error.code).to eq("organization_not_self_serve_production")
    end
  end

  context "with a stale copy of an organization that is no longer self-serve" do
    subject(:result) { described_class.call(organization: stale) }

    let(:stale) { Organization.find(organization.id) }

    before do
      stale
      organization.update_columns(self_serve: false, activation_status: "active") # rubocop:disable Rails/SkipsModelValidations
    end

    it "refuses from the row read under the lock" do
      expect(result).to be_failure
      expect(result.error.code).to eq("organization_not_self_serve_production")
    end
  end

  context "with two concurrent calls", transaction: false do
    it "activates the organization once" do
      organization_id = organization.id

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(organization: Organization.find(organization_id))
          end
        end
      end

      threads.map(&:value).each { expect(it).to be_success }

      expect(organization.reload.activation_status).to eq("active")
      expect(ApiKeys::CacheService).to have_received(:expire_all_cache).once
    end
  end
end
