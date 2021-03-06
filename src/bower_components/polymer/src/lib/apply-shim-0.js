
/**
 * The apply shim simulates the behavior of `@apply` proposed at
 * https://tabatkins.github.io/specs/css-apply-rule/.
 * The approach is to convert a property like this:
 *
 *    --foo: {color: red; background: blue;}
 *
 * to this:
 *
 *    --foo_-_color: red;
 *    --foo_-_background: blue;
 *
 * Then where `@apply --foo` is used, that is converted to:
 *
 *    color: var(--foo_-_color);
 *    background: var(--foo_-_background);
 *
 * This approach generally works but there are some issues and limitations.
 * Consider, for example, that somewhere *between* where `--foo` is set and used,
 * another element sets it to:
 *
 *    --foo: { border: 2px solid red; }
 *
 * We must now ensure that the color and background from the previous setting
 * do not apply. This is accomplished by changing the property set to this:
 *
 *    --foo_-_border: 2px solid red;
 *    --foo_-_color: initial;
 *    --foo_-_background: initial;
 *
 * This works but introduces one new issue.
 * Consider this setup at the point where the `@apply` is used:
 *
 *    background: orange;
 *    @apply --foo;
 *
 * In this case the background will be unset (initial) rather than the desired
 * `orange`. We address this by altering the property set to use a fallback
 * value like this:
 *
 *    color: var(--foo_-_color);
 *    background: var(--foo_-_background, orange);
 *    border: var(--foo_-_border);
 *
 * Note that the default is retained in the property set and the `background` is
 * the desired `orange`. This leads us to a limitation.
 *
 * Limitation 1:

 * Only properties in the rule where the `@apply`
 * is used are considered as default values.
 * If another rule matches the element and sets `background` with
 * less specificity than the rule in which `@apply` appears,
 * the `background` will not be set.
 *
 * Limitation 2:
 *
 * When using Polymer's `updateStyles` api, new properties may not be set for
 * `@apply` properties.

*/
Polymer.ApplyShim = (function(){
  'use strict';

  var styleUtil = Polymer.StyleUtil;

  var MIXIN_MATCH = styleUtil.rx.MIXIN_MATCH;
  var VAR_ASSIGN = styleUtil.rx.VAR_ASSIGN;
  // match var(--a, --b) to make var(--a, var(--b));
  var BAD_VAR = /var\(\s*(--[^,]*),\s*(--[^)]*)\)/g;
  var APPLY_NAME_CLEAN = /;\s*/m;
  var INITIAL_INHERIT = /^\s*(initial)|(inherit)\s*$/;

  // separator used between mixin-name and mixin-property-name when producing properties
  // NOTE: plain '-' may cause collisions in user styles
  var MIXIN_VAR_SEP = '_-_';

  // map of mixin to property names
  // --foo: {border: 2px} -> {properties: {(--foo, ['border'])}, dependants: {'element-name': proto}}
  var mixinMap = {};

  function mapSet(name, props) {
    name = name.trim();
    mixinMap[name] = {
      properties: props,
      dependants: {}
    };
  }

  function mapGet(name) {
    name = name.trim();
    return mixinMap[name];
  }

  function replaceInitialOrInherit(property, value) {
    var match = INITIAL_INHERIT.exec(value);
    if (match) {
      if (match[1]) {
        // initial
        // replace `initial` with the concrete initial value for this property
        value = ApplyShim._getInitialValueForProperty(property);
      } else {
        // inherit
        // with this purposfully illegal value, the variable will be invalid at
        // compute time (https://www.w3.org/TR/css-variables/#invalid-at-computed-value-time)
        // and for inheriting values, will behave similarly
        // we cannot support the same behavior for non inheriting values like 'border'
        value = 'apply-shim-inherit';
      }
    }
    return value;
  }

  // "parse" a mixin definition into a map of properties and values
  // cssTextToMap('border: 2px solid black') -> ('border', '2px solid black')
  function cssTextToMap(text) {
    var props = text.split(';');
    var property, value;
    var out = {};
    for (var i = 0, p, sp; i < props.length; i++) {
      p = props[i];
      if (p) {
        sp = p.split(':');
        // ignore lines that aren't definitions like @media
        if (sp.length > 1) {
          property = sp[0].trim();
          // some properties may have ':' in the value, like data urls
          value = replaceInitialOrInherit(property, sp.slice(1).join(':'));
          out[property] = value;
        }
      }
    }
    return out;
  }

  function invalidateMixinEntry(mixinEntry) {
    var currentProto = ApplyShim.__currentElementProto;
    var currentElementName = currentProto && currentProto.is;
    for (var elementName in mixinEntry.dependants) {
      if (elementName !== currentElementName) {
        mixinEntry.dependants[elementName].__applyShimInvalid = true;
      }
    }
  }

  function produceCssProperties(matchText, propertyName, valueProperty, valueMixin) {
    // handle case where property value is a mixin
    if (valueProperty) {
      // form: --mixin2: var(--mixin1), where --mixin1 is in the map
      styleUtil.processVariableAndFallback(valueProperty, function(prefix, value) {
        if (value && mapGet(value)) {
          valueMixin = '@apply ' + value + ';';
        }
      });
    }
    if (!valueMixin) {
      return matchText;
    }
    var mixinAsProperties = consumeCssProperties(valueMixin);
    var prefix = matchText.slice(0, matchText.indexOf('--'));
    var mixinValues = cssTextToMap(mixinAsProperties);
    var combinedProps = mixinValues;
    var mixinEntry = mapGet(propertyName);
    var oldProps = mixinEntry && mixinEntry.properties;
    if (oldProps) {
      // NOTE: since we use mixin, the map of properties is updated here
      // and this is what we want.
      combinedProps = Object.create(oldProps);
      combinedProps = Polymer.Base.mixin(combinedProps, mixinValues);
    } else {
      mapSet(propertyName, combinedProps);
    }
    var out = [];
    var p, v;
    // set variables defined by current mixin
    var needToInvalidate = false;
    for (p in combinedProps) {
      v = mixinValues[p];
      // if property not defined by current mixin, set initial
      if (v === undefined) {
        v = 'initial';
      }
      if (oldProps && !(p in oldProps)) {
        needToInvalidate = true;
      }
      out.push(propertyName + MIXIN_VAR_SEP + p + ': ' + v);
    }
    if (needToInvalidate) {
      invalidateMixinEntry(mixinEntry);
    }
    if (mixinEntry) {
      mixinEntry.properties = combinedProps;
    }
    // because the mixinMap is global, the mixin might conflict with
    // a different scope's simple variable definition:
    // Example:
    // some style somewhere:
    // --mixin1:{ ... }
    // --mixin2: var(--mixin1);
    // some other element:
    // --mixin1: 10px solid red;
    // --foo: var(--mixin1);
    // In this case, we leave the original variable definition in place.
    if (valueProperty) {
      prefix = matchText + ';' + prefix;
    }
    return prefix + out.join('; ') + ';';
  }

  // fix shim'd var syntax
  // var(--a, --b) -> var(--a,var(--b))
  function fixVars(matchText, varA, varB) {
    // if fallback doesn't exist, or isn't a broken variable, abort
    return 'var(' + varA + ',' + 'var(' + varB + '))';
  }

  // produce variable consumption at the site of mixin consumption
  // @apply --foo; -> for all props (${propname}: var(--foo_-_${propname}, ${fallback[propname]}}))
  // Example:
  // border: var(--foo_-_border); padding: var(--foo_-_padding, 2px)
  function atApplyToCssProperties(mixinName, fallbacks) {
    mixinName = mixinName.replace(APPLY_NAME_CLEAN, '');
    var vars = [];
    var mixinEntry = mapGet(mixinName);
    // if we depend on a mixin before it is created
    // make a sentinel entry in the map to add this element as a dependency for when it is defined.
    if (!mixinEntry) {
      mapSet(mixinName, {});
      mixinEntry = mapGet(mixinName);
    }
    if (mixinEntry) {
      var currentProto = ApplyShim.__currentElementProto;
      if (currentProto) {
        mixinEntry.dependants[currentProto.is] = currentProto;
      }
      var p, parts, f;
      for (p in mixinEntry.properties) {
        f = fallbacks && fallbacks[p];
        parts = [p, ': var(', mixinName, MIXIN_VAR_SEP, p];
        if (f) {
          parts.push(',', f);
        }
        parts.push(')');
        vars.push(parts.join(''));
      }
    }
    return vars.join('; ');
  }

  // replace mixin consumption with variable consumption
  function consumeCssProperties(text) {
    var m;
    // loop over text until all mixins with defintions have been applied
    while((m = MIXIN_MATCH.exec(text))) {
      var matchText = m[0];
      var mixinName = m[1];
      var idx = m.index;
      // collect properties before apply to be "defaults" if mixin might override them
      // match includes a "prefix", so find the start and end positions of @apply
      var applyPos = idx + matchText.indexOf('@apply');
      var afterApplyPos = idx + matchText.length;
      // find props defined before this @apply
      var textBeforeApply = text.slice(0, applyPos);
      var textAfterApply = text.slice(afterApplyPos);
      var defaults = cssTextToMap(textBeforeApply);
      var replacement = atApplyToCssProperties(mixinName, defaults);
      // use regex match position to replace mixin, keep linear processing time
      text = [textBeforeApply, replacement, textAfterApply].join('');
      // move regex search to _after_ replacement
      MIXIN_MATCH.lastIndex = idx + replacement.length;
    }
    return text;
  }

  var ApplyShim = {
    _measureElement: null,
    _map: mixinMap,
    _separator: MIXIN_VAR_SEP,
    transform: function(styles, elementProto) {
      this.__currentElementProto = elementProto;
      styleUtil.forRulesInStyles(styles, this._boundTransformRule);
      elementProto.__applyShimInvalid = false;
      this.__currentElementProto = null;
    },
    transformRule: function(rule) {
      rule.cssText = this.transformCssText(rule.parsedCssText);
      // :root was only used for variable assignment in property shim,
      // but generates invalid selectors with real properties.
      // replace with `:host > *`, which serves the same effect
      if (rule.selector === ':root') {
        rule.selector = ':host > *';
      }
    },
    transformCssText: function(cssText) {
      // fix shim variables
      cssText = cssText.replace(BAD_VAR, fixVars);
      // produce variables
      cssText = cssText.replace(VAR_ASSIGN, produceCssProperties);
      // consume mixins
      return consumeCssProperties(cssText);
    },
    _getInitialValueForProperty: function(property) {
      if (!this._measureElement) {
        this._measureElement = document.createElement('meta');
        this._measureElement.style.all = 'initial';
        document.head.appendChild(this._measureElement);
      }
      return window.getComputedStyle(this._measureElement).getPropertyValue(property);
    }
  };

  ApplyShim._boundTransformRule = ApplyShim.transformRule.bind(ApplyShim);
  return ApplyShim;
})();
