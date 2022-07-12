module Common
  extend ActiveSupport::Concern

  private

  def valid_date?(date)
    return false unless date

    parsed_date = Date._strptime(date)

    return false unless parsed_date

    true
  end
end