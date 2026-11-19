# frozen_string_literal: true
class AiSettingsController < ApplicationController
  before_action :require_admin

  def edit
    @settings = RedmineAi::Configuration.values
  end

  def update
    current = RedmineAi::Configuration.values
    values = params.require(:settings).permit(:enabled, :model, :instructions, :sources_json).to_h
    raise RedmineAi::Error, 'Specify a valid model name.' unless values['model'].to_s.match?(/\A[a-zA-Z0-9_.:-]{1,100}\z/)
    raise RedmineAi::Error, 'Administrator instructions exceed 8,000 characters.' if values['instructions'].to_s.size > 8000
    raise RedmineAi::Error, 'Sources configuration exceeds 100 KB.' if values['sources_json'].to_s.bytesize > 100_000
    RedmineAi::Configuration.sources(values['sources_json'])
    key = params[:api_key].to_s.strip
    raise RedmineAi::Error, 'Invalid API key length.' if key.bytesize > 1000
    encrypted = current['api_key_encrypted']
    encrypted = nil if params[:clear_api_key] == '1'
    encrypted = RedmineAi::Configuration.encryptor.encrypt_and_sign(key) unless key.empty?
    Setting.plugin_redmine_ai_integration = values.merge('api_key_encrypted' => encrypted)
    flash[:notice] = 'AI settings saved.'
    redirect_to ai_settings_path
  rescue RedmineAi::Error => exception
    flash.now[:error] = exception.message
    @settings = current.merge(values || {})
    render :edit
  end
end
