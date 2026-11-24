# frozen_string_literal: true

# Guards Cloud self-serve mutations and resolvers: refused unless LAGO_SELF_SERVE_ENABLED is on.
module RequiresSelfServe
  def ready?(**args)
    ensure_self_serve_available!

    super
  end

  private

  def ensure_self_serve_available!
    raise forbidden_error(code: "self_serve_disabled") unless Lago::SelfServe.enabled?
  end
end
