# frozen_string_literal: true

class TaxHelper
  def self.applied_taxes(object)
    slim_template = <<-SLIM_TEMPLATE
- (applied_taxes.present? ? applied_taxes.pluck(:tax_rate) : [0.0]).each do |tax|
  div = tax.to_s + "%"
SLIM_TEMPLATE

    Slim::Template.new { slim_template }.render(object)
  end
end
