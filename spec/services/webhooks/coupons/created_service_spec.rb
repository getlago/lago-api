# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Coupons::CreatedService do
  subject(:webhook_service) { described_class.new(object: coupon) }

  let(:organization) { create(:organization) }
  let(:coupon) { create(:coupon, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "coupon.created", "coupon", {
      "lago_id" => String,
      "name" => String,
      "code" => String,
      "coupon_type" => String
    }
  end
end
