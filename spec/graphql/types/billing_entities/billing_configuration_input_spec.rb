# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::BillingEntities::BillingConfigurationInput do
  subject { described_class }

  it { is_expected.to accept_argument(:document_locale).of_type("String") }
  it { is_expected.to accept_argument(:invoice_footer).of_type("String") }
  it { is_expected.to accept_argument(:invoice_grace_period).of_type("Int") }
end
