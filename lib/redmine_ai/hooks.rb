# frozen_string_literal: true
module RedmineAi
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_show_details_bottom, partial: 'ai_enhancements/buttons'
  end
end
