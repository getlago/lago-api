# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntity::AppliedTax do
  subject(:billing_entity_applied_tax) { create(:billing_entity_applied_tax) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billing_entity) { create_default(:billing_entity) }

  it { is_expected.to belong_to(:billing_entity) }
  it { is_expected.to belong_to(:tax) }
  it { is_expected.to belong_to(:organization) }
end
