# frozen_string_literal: true

module Rails::ConsoleMethods
  def find(id)
    if /^gid/.match?(id)
      GlobalID::Locator.locate(id)
    elsif EmailValidator::EMAIL_REGEXP.match?(id)
      User.find_by email: id
    else
      raise "Don't know how to resolve this ¯\\_(ツ)_/¯. Please provide a valid email or Global ID."
    end
  end
end
