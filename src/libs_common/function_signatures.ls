lib_name_to_func_names_and_signatures =
  log_utils:
    addtolog: ['name', 'data']
    getlog: 'name'
    clearlog: 'name'
    log_impression: 'name'
    log_action: ['name', 'data']
  db_utils:
    addtolist: ['name', 'data']
    getlist: 'name'
    clearlist: 'name'
    getvar: 'key'
    setvar: ['key', 'val']
    addtovar: ['key', 'val']
    getkey_dictdict: ['name', 'key', 'key2']
    getdict_for_key_dictdict: ['name', 'key']
    getdict_for_key2_dictdict: ['name', 'key2']
  intervention_utils:
    set_intervention_enabled: 'name'
    set_intervention_disabled: 'name'
    set_intervention_disabled_permanently: 'name'
  tab_utils:
    close_selected_tab: []
    open_url_in_new_tab: 'url'
  history_utils:
    get_pages_visited_today: []
    get_pages_visited_all_time: []
    get_work_pages_visited_today: []
    get_productivity_classifications: []
  goal_utils:
    get_goal_target: ['goal_name']
    set_goal_target: ['goal_name', 'target_value']
    get_all_goal_targets: []
    list_goal_info_for_enabled_goals: []
  goal_progress:
    get_progress_on_enabled_goals_this_week: []

func_name_to_signature = {}
for lib_name,funcs of lib_name_to_func_names_and_signatures
  for func_name,func_signature of funcs
    func_name_to_signature[func_name] = func_signature

export list_functions_in_lib = (lib_name) ->
  return Object.keys(lib_name_to_func_names_and_signatures[lib_name])

export list_libs = ->
  return Object.keys(lib_name_to_func_names_and_signatures)

export get_function_signature = (func_name) ->
  return func_name_to_signature[func_name]
