# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntity::AppliedTax, type: :model do
  subject(:billing_entity_applied_tax) { create(:billing_entity_applied_tax) }

  it { is_expected.to belong_to(:billing_entity) }
  it { is_expected.to belong_to(:tax) }

  it { is_expected.to validate_uniqueness_of(:tax_id).scoped_to(:billing_entity_id) }
end
