# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedInvoiceCustomSection, type: :model do
  subject(:applied_invoice_custom_section) { create(:applied_invoice_custom_section) }

  it { is_expected.to belong_to(:invoice) }
end
