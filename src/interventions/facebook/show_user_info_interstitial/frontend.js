(() => {

  if (window.show_user_info_interstitial) {
    return
  }
  window.show_user_info_interstitial = true



  require('enable-webcomponents-in-content-scripts')
  

  
  if (document.querySelector("._1k67") === null)  { //checks if user is logged in 
    return;
  }

  const $ = require('jquery')
  require('components/interstitial-screen.deps')
  const {
    get_minutes_spent_on_domain_today,
    get_visits_to_domain_today
  } = require('libs_common/time_spent_utils')

  const {
    log_impression,
    log_action,
  } = require('libs_common/log_utils')

  const {
    url_to_domain
  } = require('libs_common/domain_utils')


  get_minutes_spent_on_domain_today(url_to_domain(window.location.href), function(numMins){    
    get_visits_to_domain_today(url_to_domain(window.location.href), function(numVisits) {
      
      var titleString = 'You have visited ' + url_to_domain(window.location.href) +' ' + numVisits + ' times and spent '+ numMins + ' minutes there today.'
      var buttonText = 'Click to continue to Facebook'
      var buttonText2 = 'Close Facebook'

      var interst_screen = $('<interstitial-screen class="interst_screen">')
      interst_screen.attr('intervention', intervention.name)
      interst_screen.attr('btn-txt', buttonText)
      interst_screen.attr('btn-txt2', buttonText2)
      interst_screen.attr('title-text', titleString)
      log_impression(intervention.name)
      $(document.body).append(interst_screen)
    })
  });

  document.body.addEventListener('disable_intervention', () => {
    $('.interst_screen').remove();
  });
  


})()