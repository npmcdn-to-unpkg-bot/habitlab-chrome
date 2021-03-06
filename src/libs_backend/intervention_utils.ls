$ = require 'jquery'

require! {
  prelude
  moment
}

{
  memoizeSingleAsync
} = require 'libs_common/memoize'

{
  setkey_dictdict
  getkey_dictdict
  getdict_for_key_dictdict
} = require 'libs_backend/db_utils'

{
  gexport
  gexport_module
} = require 'libs_common/gexport'

{
  as_dictset
  as_array
} = require 'libs_common/collection_utils'

{cfy, yfy} = require 'cfy'

getInterventionInfo = cfy (intervention_name) ->*
  intervention_info_text = yield $.get "/interventions/#{intervention_name}/info.json"
  intervention_info = JSON.parse intervention_info_text
  intervention_info.name = intervention_name
  intervention_info.sitename = intervention_name.split('/')[0]
  return intervention_info

export set_override_enabled_interventions_once = (intervention_name) ->
  localStorage.setItem('override_enabled_interventions_once', JSON.stringify([intervention_name]))
  return

export get_enabled_interventions_with_override = cfy ->*
  override_enabled_interventions = localStorage.getItem('override_enabled_interventions_once')
  if override_enabled_interventions?
    #localStorage.removeItem('override_enabled_interventions_once')
    return as_dictset(JSON.parse(override_enabled_interventions))
  enabled_interventions = yield intervention_manager.get_enabled_interventions_for_today()
  return enabled_interventions

export get_enabled_interventions_with_override_for_visit = cfy ->*
  override_enabled_interventions = localStorage.getItem('override_enabled_interventions_once')
  if override_enabled_interventions?
    #localStorage.removeItem('override_enabled_interventions_once')
    return as_dictset(JSON.parse(override_enabled_interventions))
  enabled_interventions = yield intervention_manager.get_enabled_interventions_for_visit()
  return enabled_interventions

/*
export get_enabled_interventions = cfy ->*
  enabled_interventions = yield intervention_manager.get_enabled_interventions_for_today()
  return enabled_interventions

export set_enabled_interventions = cfy (enabled_interventions) ->*
  yield intervention_manager.set_enabled_interventions_for_today_manual enabled_interventions
  return
*/

export is_it_outside_work_hours = ->
  {work_hours_only ? 'false', start_mins_since_midnight ? '0', end_mins_since_midnight ? '1440'} = localStorage
  work_hours_only = work_hours_only == 'true'
  start_mins_since_midnight = parseInt start_mins_since_midnight
  end_mins_since_midnight = parseInt end_mins_since_midnight
  mins_since_midnight = moment().hours()*60 + moment().minutes()
  if work_hours_only and not (start_mins_since_midnight <= mins_since_midnight <= end_mins_since_midnight)
    return true
  return false

export get_enabled_interventions = cfy ->*
  enabled_interventions = yield intervention_manager.get_currently_enabled_interventions()
  return enabled_interventions

export set_enabled_interventions = cfy (enabled_interventions) ->*
  yield intervention_manager.set_currently_enabled_interventions_manual enabled_interventions

export set_intervention_enabled = cfy (intervention_name) ->*
  enabled_interventions = yield get_enabled_interventions()
  if enabled_interventions[intervention_name]
    return
  enabled_interventions[intervention_name] = true
  yield set_enabled_interventions enabled_interventions

export set_intervention_disabled_permanently = cfy (intervention_name) ->*
  yield set_intervention_manually_managed intervention_name
  enabled_interventions = yield get_enabled_interventions()
  if not enabled_interventions[intervention_name]
    return
  enabled_interventions[intervention_name] = false
  yield set_enabled_interventions enabled_interventions

export set_intervention_disabled = cfy (intervention_name) ->*
  enabled_interventions = yield get_enabled_interventions()
  if not enabled_interventions[intervention_name]
    return
  enabled_interventions[intervention_name] = false
  yield set_enabled_interventions enabled_interventions

export is_intervention_enabled = cfy (intervention_name) ->*
  enabled_interventions = yield get_enabled_interventions()
  return enabled_interventions[intervention_name]

export list_all_interventions = memoizeSingleAsync cfy ->*
  cached_list_all_interventions = localStorage.getItem 'cached_list_all_interventions'
  if cached_list_all_interventions?
    return JSON.parse cached_list_all_interventions
  interventions_list_text = yield $.get '/interventions/interventions.json'
  interventions_list = JSON.parse interventions_list_text
  localStorage.setItem 'cached_list_all_interventions', interventions_list_text
  return interventions_list

export get_interventions = memoizeSingleAsync cfy ->*
  cached_get_interventions = localStorage.getItem 'cached_get_interventions'
  if cached_get_interventions?
    return JSON.parse cached_get_interventions
  interventions_to_goals_promises = goal_utils.get_interventions_to_goals()
  interventions_list = yield list_all_interventions()
  output = {}
  fix_content_script_options = (options, intervention_name) ->
    if typeof options == 'string'
      options = {path: options}
    if options.path[0] == '/'
      options.path = options.path.substr(1)
    else
      options.path = "interventions/#{intervention_name}/#{options.path}"
    if not options.run_at?
      options.run_at = 'document_end' # document_start
    if not options.all_frames?
      options.all_frames = false
    return options
  fix_background_script_options = (options, intervention_name) ->
    if typeof options == 'string'
      options = {path: options}
    if options.path[0] == '/'
      options.path = options.path.substr(1)
    else
      options.path = "interventions/#{intervention_name}/#{options.path}"
    return options
  fix_intervention_parameter = (parameter, intervention_info) ->
    if not parameter.name?
      console.log "warning: missing parameter.name for intervention #{intervention_info.name}"
    if not parameter.default?
      console.log "warning: missing parameter.default for intervention #{intervention_info.name}"
    if not parameter.type?
      parameter.type = 'string'
      return
    curtype = parameter.type.toLowerCase()
    if curtype.startsWith('str')
      parameter.type = 'string'
      return
    if curtype.startsWith('int')
      parameter.type = 'int'
      return
    if curtype.startsWith('float') or curtype.startsWith('real') or curtype.startsWith('double') or curtype.startsWith('num')
      parameter.type = 'float'
      return
    if curtype.startsWith('bool')
      parameter.type = 'bool'
      return
    console.log "warning: invalid parameter.type #{curtype} for intervention #{intervention_info.name}"
  intervention_name_to_info_promises = {[intervention_name, getInterventionInfo(intervention_name)] for intervention_name in interventions_list}
  [intervention_name_to_info, interventions_to_goals] = yield [intervention_name_to_info_promises, interventions_to_goals_promises]
  for intervention_name in interventions_list
    intervention_info = intervention_name_to_info[intervention_name]
    if not intervention_info.nomatches?
      intervention_info.nomatches = []
    if not intervention_info.matches?
      intervention_info.matches = []
    if not intervention_info.content_scripts?
      intervention_info.content_scripts = []
    if not intervention_info.background_scripts?
      intervention_info.background_scripts = []
    if not intervention_info.parameters?
      intervention_info.parameters = []
    if not intervention_info.categories?
      intervention_info.categories = []
    if not intervention_info.conflicts?
      intervention_info.conflicts = []
    intervention_info.parameters.push {
      name: 'debug'
      description: 'Insert debug console'
      type: 'bool'
      default: false
    }
    for parameter in intervention_info.parameters
      fix_intervention_parameter(parameter, intervention_info)
    intervention_info.params = {[x.name, x] for x in intervention_info.parameters}
    intervention_info.content_script_options = [fix_content_script_options(x, intervention_name) for x in intervention_info.content_scripts]
    intervention_info.background_script_options = [fix_background_script_options(x, intervention_name) for x in intervention_info.background_scripts]
    intervention_info.match_regexes = [new RegExp(x) for x in intervention_info.matches]
    intervention_info.nomatch_regexes = [new RegExp(x) for x in intervention_info.nomatches]
    intervention_info.goals = interventions_to_goals[intervention_name]
    output[intervention_name] = intervention_info
  category_to_interventions = {}
  for intervention_name in interventions_list
    intervention_info = output[intervention_name]
    for category in intervention_info.categories
      if not category_to_interventions[category]?
        category_to_interventions[category] = []
      category_to_interventions[category].push intervention_name
  for intervention_name in interventions_list
    intervention_info = output[intervention_name]
    for category in intervention_info.categories
      for conflict in category_to_interventions[category]
        if conflict == intervention_name
          continue
        intervention_info.conflicts.push conflict
  localStorage.setItem 'cached_get_interventions', JSON.stringify(output)
  return output

export list_enabled_interventions_for_location = cfy (location) ->*
  available_interventions = yield list_available_interventions_for_location(location)
  enabled_interventions = yield get_enabled_interventions()
  return available_interventions.filter((x) -> enabled_interventions[x])

/*
export list_all_enabled_interventions_for_location_with_override = cfy (location) ->*
  # TODO this no longer works on new days. need to persist enabled interventions across days
  override_enabled_interventions = localStorage.getItem('override_enabled_interventions_once')
  if override_enabled_interventions?
    #localStorage.removeItem('override_enabled_interventions_once')
    return as_array(JSON.parse(override_enabled_interventions))
  available_interventions = yield list_available_interventions_for_location(location)
  enabled_interventions = yield intervention_manager.get_most_recent_enabled_interventions()
  return available_interventions.filter((x) -> enabled_interventions[x])
*/

export list_all_enabled_interventions_for_location = cfy (location) ->*
  #override_enabled_interventions = localStorage.getItem('override_enabled_interventions_once')
  #if override_enabled_interventions?
  #  return as_array(JSON.parse(override_enabled_interventions))
  available_interventions = yield list_available_interventions_for_location(location)
  enabled_interventions = yield intervention_manager.get_currently_enabled_interventions()
  return available_interventions.filter((x) -> enabled_interventions[x])

export list_enabled_nonconflicting_interventions_for_location = cfy (location) ->*
  available_interventions = yield list_available_interventions_for_location(location)
  enabled_interventions = yield get_enabled_interventions_with_override_for_visit()
  all_interventions = yield get_interventions()
  enabled_interventions_for_location = available_interventions.filter((x) -> enabled_interventions[x])
  output = []
  output_set = {}
  for intervention_name in enabled_interventions_for_location
    intervention_info = all_interventions[intervention_name]
    keep_enabled = true
    for conflict in intervention_info.conflicts
      if output_set[conflict]?
        keep_enabled = false
    if keep_enabled
      output.push intervention_name
      output_set[intervention_name] = true
  return output

export list_available_interventions_for_location = cfy (location) ->*
  all_interventions = yield get_interventions()
  possible_interventions = []
  for intervention_name,intervention_info of all_interventions
    blacklisted = false
    for regex in intervention_info.nomatch_regexes
      if regex.test(location)
        blacklisted = true
        break
    if blacklisted
      continue
    matches = false
    for regex in intervention_info.match_regexes
      if regex.test(location)
        matches = true
        break
    if matches
      possible_interventions.push intervention_name
  return possible_interventions

export get_manually_managed_interventions_localstorage = cfy ->*
  manually_managed_interventions_str = localStorage.getItem('manually_managed_interventions')
  if not manually_managed_interventions_str?
    manually_managed_interventions = {}
  else
    manually_managed_interventions = JSON.parse manually_managed_interventions_str
  return manually_managed_interventions

export get_manually_managed_interventions = get_manually_managed_interventions_localstorage

/*
export get_most_recent_manually_enabled_interventions = cfy ->*
  enabled_interventions = yield intervention_manager.get_most_recent_enabled_interventions()
  manually_managed_interventions = yield get_manually_managed_interventions()
  output = {}
  for intervention_name,is_enabled of enabled_interventions
    output[intervention_name] = is_enabled and manually_managed_interventions[intervention_name]
  return output

export get_most_recent_manually_disabled_interventions = cfy ->*
  enabled_interventions = yield intervention_manager.get_most_recent_enabled_interventions()
  manually_managed_interventions = yield get_manually_managed_interventions()
  output = {}
  for intervention_name,is_enabled of enabled_interventions
    output[intervention_name] = (!is_enabled) and manually_managed_interventions[intervention_name]
  return output
*/

export set_manually_managed_interventions = cfy (manually_managed_interventions) ->*
  localStorage.setItem 'manually_managed_interventions', JSON.stringify(manually_managed_interventions)
  return

export set_intervention_manually_managed = cfy (intervention_name) ->*
  manually_managed_interventions = yield get_manually_managed_interventions()
  if manually_managed_interventions[intervention_name]
    return
  manually_managed_interventions[intervention_name] = true
  yield set_manually_managed_interventions manually_managed_interventions

export set_intervention_automatically_managed = cfy (intervention_name) ->*
  manually_managed_interventions = yield get_manually_managed_interventions()
  if not manually_managed_interventions[intervention_name]
    return
  manually_managed_interventions[intervention_name] = false
  yield set_manually_managed_interventions manually_managed_interventions

export list_available_interventions_for_enabled_goals = cfy ->*
  # outputs a list of intervention names
  interventions_to_goals = yield goal_utils.get_interventions_to_goals()
  enabled_goals = yield goal_utils.get_enabled_goals()
  output = []
  output_set = {}
  for intervention_name,goals of interventions_to_goals
    for goal in goals
      if enabled_goals[goal.name]? and not output_set[intervention_name]?
        output.push intervention_name
        output_set[intervention_name] = true
  return output

export list_available_interventions_for_goal = cfy (goal_name) ->*
  # outputs a list of intervention names
  interventions_to_goals = yield goal_utils.get_interventions_to_goals()
  output = []
  output_set = {}
  for intervention_name,goals of interventions_to_goals
    for goal in goals
      if goal_name == goal.name and not output_set[intervention_name]?
        output.push intervention_name
        output_set[intervention_name] = true
  return output

cast_to_bool = (parameter_value) ->
  if typeof(parameter_value) != 'string'
    return Boolean(parameter_value)
  if parameter_value.toLowerCase() == 'false'
    return false
  return true

cast_to_type = (parameter_value, type_name) ->
  if type_name == 'string'
    return parameter_value.toString()
  if type_name == 'int'
    return parseInt(parameter_value)
  if type_name == 'float'
    return parseFloat(parameter_value)
  if type_name == 'bool'
    return cast_to_bool(parameter_value)
  return parameter_value

export set_intervention_parameter = cfy (intervention_name, parameter_name, parameter_value) ->*
  yield setkey_dictdict 'intervention_to_parameters', intervention_name, parameter_name, parameter_value

get_intervention_parameter_type = cfy (intervention_name, parameter_name) ->*
  interventions = yield get_interventions()
  intervention_info = interventions[intervention_name]
  parameter_type = intervention_info.params[parameter_name].type
  return parameter_type

export get_intervention_parameter_default = cfy (intervention_name, parameter_name) ->*
  interventions = yield get_interventions()
  intervention_info = interventions[intervention_name]
  parameter_type = intervention_info.params[parameter_name].type
  parameter_value = intervention_info.params[parameter_name].default
  return cast_to_type(parameter_value, parameter_type)

export get_intervention_parameters_default = cfy (intervention_name) ->*
  interventions = yield get_interventions()
  intervention_info = interventions[intervention_name]
  return {[x.name, cast_to_type(x.default, x.type)] for x in intervention_info.parameters}

export get_intervention_parameter = cfy (intervention_name, parameter_name) ->*
  result = yield getkey_dictdict 'intervention_to_parameters', intervention_name, parameter_name
  parameter_type = yield get_intervention_parameter_type(intervention_name, parameter_name)
  if result?
    return cast_to_type(result, parameter_type)
  yield get_intervention_parameter_default(intervention_name, parameter_name)

export get_intervention_parameters = cfy (intervention_name) ->*
  results = yield getdict_for_key_dictdict 'intervention_to_parameters', intervention_name
  default_parameters = yield get_intervention_parameters_default(intervention_name)
  interventions = yield get_interventions()
  intervention_info = interventions[intervention_name]
  output = {}
  for k,v of default_parameters
    parameter_value = results[k] ? default_parameters[k]
    parameter_type = intervention_info.params[k].type
    output[k] = cast_to_type(parameter_value, parameter_type)
  return output

export get_effectiveness_of_intervention_for_goal = cfy (intervention_name, goal_name) ->*
  progress_info_base = yield goal_progress.get_progress_on_goal_days_since_today goal_name, 0
  days_deployed = yield intervention_manager.get_days_since_today_on_which_intervention_was_deployed intervention_name
  progress_list = []
  for day in days_deployed
    progress_info = yield goal_progress.get_progress_on_goal_days_since_today goal_name, day
    progress_list.push progress_info.progress
  if progress_list.length > 0
    progress_info_base.progress = prelude.average progress_list
    progress_info_base.message = "#{progress_info_base.progress} minutes"
  else
    progress_info_base.progress = NaN
    progress_info_base.message = "no data"
  return progress_info_base

export get_effectiveness_of_all_interventions_for_goal = cfy (goal_name) ->*
  output = {}
  interventions = yield list_available_interventions_for_goal goal_name
  for intervention_name in interventions
    progress_info = yield get_effectiveness_of_intervention_for_goal intervention_name, goal_name
    output[intervention_name] = progress_info
  return output

export get_goals_and_interventions = cfy ->*
  
  intervention_name_to_info = yield get_interventions()
  console.log intervention_name_to_info
  enabled_interventions = yield get_enabled_interventions()
  enabled_goals = yield goal_utils.get_enabled_goals()
  all_goals = yield goal_utils.get_goals()
  manually_managed_interventions = yield get_manually_managed_interventions()
  goal_to_interventions = {}
  for intervention_name,intervention_info of intervention_name_to_info
    for goal in intervention_info.goals
      goalname = goal.name
      if not goal_to_interventions[goalname]?
        goal_to_interventions[goalname] = []
      goal_to_interventions[goalname].push intervention_info
  list_of_goals_and_interventions = []
  list_of_goals = prelude.sort as_array(enabled_goals)
  for goalname in list_of_goals
    current_item = {goal: all_goals[goalname]}
    current_item.interventions = prelude.sort-by (.name), goal_to_interventions[goalname]
    for intervention in current_item.interventions
      intervention.enabled_goals = []
      #if intervention.goals?
      #  intervention.enabled_goals = [goal for goal in intervention.goals when enabled_goals[goal.name]]
      intervention.enabled = (enabled_interventions[intervention.name] == true)
      intervention.automatic = (manually_managed_interventions[intervention.name] != true)
    list_of_goals_and_interventions.push current_item
  return list_of_goals_and_interventions


intervention_manager = require 'libs_backend/intervention_manager'
goal_utils = require 'libs_backend/goal_utils'
goal_progress = require 'libs_backend/goal_progress'

gexport_module 'intervention_utils', -> eval(it)
