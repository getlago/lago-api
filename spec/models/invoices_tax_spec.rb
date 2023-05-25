# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoicesTax, type: :model do
  subject(:invoices_tax) { create(:invoices_tax) }

  it_behaves_like 'paper_trail traceable'
end
