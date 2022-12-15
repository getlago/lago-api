# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::CouponSerializer do
  subject(:serializer) { described_class.new(coupon, root_name: 'coupon') }

  let(:coupon) { create(:coupon) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['coupon']['lago_id']).to eq(coupon.id)
      expect(result['coupon']['name']).to eq(coupon.name)
      expect(result['coupon']['code']).to eq(coupon.code)
      expect(result['coupon']['amount_cents']).to eq(coupon.amount_cents)
      expect(result['coupon']['amount_currency']).to eq(coupon.amount_currency)
      expect(result['coupon']['expiration']).to eq(coupon.expiration)
      expect(result['coupon']['expiration_at']).to eq(coupon.expiration_at&.iso8601)
      expect(result['coupon']['created_at']).to eq(coupon.created_at.iso8601)
    end
  end

  it 'serializes the legacy fields' do
    result = JSON.parse(serializer.to_json)

    expect(result['coupon']['expiration_date']).to eq(coupon.expiration_at&.to_date&.iso8601)
  end
end
