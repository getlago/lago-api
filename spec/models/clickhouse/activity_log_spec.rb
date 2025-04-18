# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::ActivityLog, type: :model, clickhouse: true do
  subject(:activity_log) { create(:clickhouse_activity_log) }

  describe "#ensure_activity_id" do
    it "sets the activity_id if it is not set" do
      expect(activity_log.activity_id).to be_present
    end
  end

  describe "#organization" do
    it "returns the organization" do
      expect(activity_log.organization).to be_a(Organization)
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

  describe "#resource" do
    it "returns the resource" do
      expect(activity_log.resource).to be_a(BillableMetric)
    end
  end
end
