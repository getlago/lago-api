# frozen_string_literal: true

class FeeDisplayHelper
  def self.grouped_by_display(fee)
    return '' unless fee.charge?
    return '' if fee.charge.properties['grouped_by'].blank?
    return '' if fee.grouped_by.values.compact.blank?

    " • #{fee.grouped_by.values.compact.join(" • ")}"
  end
end
