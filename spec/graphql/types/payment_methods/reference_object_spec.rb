# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentMethods::ReferenceObject do
  subject { described_class }

  it { is_expected.to have_field(:payment_method_id).of_type("ID") }
  it { is_expected.to have_field(:payment_method_type).of_type("PaymentMethodTypeEnum") }
end
