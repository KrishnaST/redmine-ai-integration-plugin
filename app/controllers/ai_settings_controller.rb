# frozen_string_literal: true
class AiSettingsController < ApplicationController
  before_action :require_admin

  def edit
    load_form
  end

  def update
    current = RedmineAi::Configuration.values
    values = params.require(:settings).permit(:enabled, :model, :reasoning_effort, code_role_ids: []).to_h
    RedmineAi::SettingsService.save(values, source_rows: params[:sources_present] == '1' ? source_rows : nil,
      api_key: params[:api_key], clear_api_key: params[:clear_api_key] == '1')
    flash[:notice] = 'AI settings saved.'
    redirect_to ai_settings_path
  rescue RedmineAi::Error => exception
    flash.now[:error] = exception.message
    load_form
    @settings = current.merge(values || {}).except('api_key_encrypted')
    render :edit
  end

  def refresh_models
    count = RedmineAi::Models.refresh.size
    flash[:notice] = "Available model list refreshed (#{count} text-model IDs). Check the selected model supports Responses and structured output."
    redirect_to ai_settings_path
  rescue StandardError => exception
    flash[:error] = exception.is_a?(RedmineAi::Error) ? exception.message : 'Could not refresh models. Check API connectivity and key permissions.'
    redirect_to ai_settings_path
  end

  def reload_sources
    RedmineAi::SourceChecks.enqueue(User.current)
    flash[:notice] = 'Source tests queued. Folders, metadata and approved samples are checked without calling OpenAI.'
    redirect_to ai_settings_path
  rescue StandardError
    flash[:error] = 'Could not queue source tests. Check the job backend and save settings first.'
    redirect_to ai_settings_path
  end

  private

  def load_form
    @settings = RedmineAi::Configuration.values
    @sources = RedmineAi::Configuration.sources.map { |source| source.merge('id' => RedmineAi::SourceConfiguration.id(source)) }
    @models = RedmineAi::Models.options
    @code_roles = Role.where(builtin: 0).order(:name).pluck(:name, :id)
    @projects = Project.order(:name).pluck(:name, :id)
    @source_check = @settings['source_check'] || {}
  end

  def source_rows
    rows = params[:sources]
    return [] if rows.nil?
    raise RedmineAi::Error, 'Invalid source form.' unless rows.respond_to?(:each_value)
    rows.each_value.map do |row|
      value = row.permit(:id, :name, :type, :root, :revision, :allow_code_changes, :db_type, :host, :port, :database,
                        :schema, :username, :password, :clear_password, :include_table_data, project_ids: []).to_h
      tables = row[:sample_tables]
      value['sample_tables'] = tables.respond_to?(:each_value) ? tables.each_value.map { |table| table.permit(:table, :columns, :limit).to_h } : []
      value
    end
  end
end
