# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::SecurityLog, clickhouse: true do
  subject(:security_log) { create(:clickhouse_security_log) }

  describe "associations" do
    it do
      expect(security_log).to belong_to(:organization)
      expect(security_log).to belong_to(:user).optional
      expect(security_log).to belong_to(:api_key).optional
    end
  end

  describe "#ensure_log_id" do
    it "sets the log_id if it is not set" do
      expect(security_log.log_id).to be_present
    end
  end
end
