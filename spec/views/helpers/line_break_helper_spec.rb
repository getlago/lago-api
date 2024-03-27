# frozen_string_literal: true

require "rails_helper"

RSpec.describe LineBreakHelper do
  subject(:helper) { described_class }

  describe ".break_lines" do
    it 'replaces \n with <br\>' do
      html = helper.break_lines("t\nt")

      expect(html).to eq("t<br/>t")
    end
  end
end
