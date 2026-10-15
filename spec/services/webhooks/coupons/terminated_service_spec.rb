# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Coupons::TerminatedService do
  subject(:webhook_service) { described_class.new(object: coupon) }

  let(:organization) { create(:organization) }
  let(:coupon) { create(:coupon, organization:, status: :terminated, terminated_at: Time.current) }

  describe ".call" do
    it_behaves_like "creates webhook", "coupon.terminated", "coupon", {
      "lago_id" => String,
      "code" => String,
      "terminated_at" => String
    }
  end
end
