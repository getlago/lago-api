# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceCustomSection, type: :model do
  subject(:invoice_custom_section) { create(:invoice_custom_section) }

  it { is_expected.to belong_to(:organization) }
end
