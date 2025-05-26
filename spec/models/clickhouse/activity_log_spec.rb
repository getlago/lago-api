# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::ActivityLog, type: :model, clickhouse: true do
  subject(:activity_log) { create(:clickhouse_activity_log) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:resource) }
  it { is_expected.to belong_to(:customer).optional }
  it { is_expected.to belong_to(:subscription).optional }

  describe "#ensure_activity_id" do
    it "sets the activity_id if it is not set" do
      expect(activity_log.activity_id).to be_present
    end
  end

  describe "#user" do
    it "returns the user" do
      expect(activity_log.user).to be_a(User)
    end
  end

  describe "#api_key" do
    it "returns the api key" do
      expect(activity_log.api_key).to be_a(ApiKey)
    end
  end

  describe "#customer" do
    it "returns the customer" do
      expect(activity_log.customer).to be_a(Customer)
    end
  end

  describe "#subscription" do
    it "returns the subscription" do
      expect(activity_log.subscription).to be_a(Subscription)
    end
  end
end
