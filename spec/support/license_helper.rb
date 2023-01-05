# frozen_string_literal: true

module LicenseHelper
  def lago_premium!
    License.instance_variable_set(:@premium, true)
    yield
    License.instance_variable_set(:@premium, false)
  end
end
