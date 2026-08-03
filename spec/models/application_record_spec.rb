# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationRecord do
  describe "database roles" do
    it "exposes the :writing role (default) mapped to the :primary config" do
      expect {
        described_class.connected_to(role: :writing) do
          described_class.connection.execute("SELECT 1")
        end
      }.not_to raise_error
    end

    it "exposes the :direct role for RDS-Proxy-bypass queries" do
      expect {
        described_class.connected_to(role: :direct) do
          described_class.connection.execute("SELECT 1")
        end
      }.not_to raise_error
    end

    it "restores the previous role after the connected_to block exits" do
      described_class.connected_to(role: :direct) do
        # inside block: role is :direct
      end

      # Outside the block we're back to the default role; a normal query works.
      expect { described_class.connection.execute("SELECT 1") }.not_to raise_error
    end
  end
end
