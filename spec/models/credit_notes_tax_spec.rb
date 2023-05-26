# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotesTax, type: :model do
  subject(:credit_notes_tax) { create(:credit_notes_tax) }

  it_behaves_like 'paper_trail traceable'
end
