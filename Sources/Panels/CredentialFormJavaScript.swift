import Foundation

/// JavaScript source strings for login form detection and credential filling.
enum CredentialFormJavaScript {

    /// Bootstrap script injected at document end in all frames.
    /// Detects login forms and reports to Swift via WKScriptMessageHandler.
    static let formDetectionScript = """
    (() => {
      if (window.__cmuxCredDetectInstalled) return;
      window.__cmuxCredDetectInstalled = true;

      function isVisible(el) {
        if (!el) return false;
        const s = window.getComputedStyle(el);
        return s.display !== 'none' && s.visibility !== 'hidden'
          && s.opacity !== '0' && el.offsetParent !== null;
      }

      function detectLoginForm() {
        const pwFields = [...document.querySelectorAll('input[type="password"]')].filter(isVisible);
        if (pwFields.length === 0) return null;

        const pw = pwFields[0];
        const form = pw.closest('form') || document;
        const selectors = [
          'input[autocomplete="username"]', 'input[autocomplete="email"]',
          'input[name="login"]', 'input[name="username"]', 'input[name="email"]',
          'input[name="user"]', 'input[name="loginfmt"]',
          'input[id="login_field"]', 'input[id="identifierId"]',
          'input[id="okta-signin-username"]', 'input[id="email"]',
          'input[type="email"]',
          'input[type="text"]:not([autocomplete="off"])'
        ];
        let userField = null;
        for (const sel of selectors) {
          const c = [...form.querySelectorAll(sel)].filter(isVisible);
          if (c.length > 0) { userField = c[0]; break; }
        }
        return { hasUsername: !!userField, hasPassword: true };
      }

      function scan() {
        const result = detectLoginForm();
        if (result) {
          try {
            window.webkit.messageHandlers.cmuxCredentialFormDetected.postMessage({
              domain: window.location.hostname,
              hasUsername: result.hasUsername,
              hasPassword: result.hasPassword
            });
          } catch (_) {}
        }
      }

      // Scan on load and on DOM mutations (debounced, stops after first detection)
      let __cmuxScanTimer = null;
      let __cmuxDetected = false;
      function debouncedScan() {
        if (__cmuxDetected) return;
        if (__cmuxScanTimer) clearTimeout(__cmuxScanTimer);
        __cmuxScanTimer = setTimeout(() => {
          scan();
          if (detectLoginForm()) { __cmuxDetected = true; observer.disconnect(); }
        }, 300);
      }
      scan();
      if (detectLoginForm()) { __cmuxDetected = true; }
      const observer = new MutationObserver(debouncedScan);
      if (!__cmuxDetected) {
        observer.observe(document.body || document.documentElement, {
          childList: true, subtree: true
        });
      }
    })()
    """

    /// Escape a string for safe embedding in a JS single-quoted string literal.
    private static func escapeForJS(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Returns JS that fills a login form with the given credentials.
    /// Uses native setter bypass for React/Vue/Angular compatibility.
    static func fillScript(username: String, password: String) -> String {
        let escapedUser = escapeForJS(username)
        let escapedPass = escapeForJS(password)

        return """
        (() => {
          function isVisible(el) {
            if (!el) return false;
            const s = window.getComputedStyle(el);
            return s.display !== 'none' && s.visibility !== 'hidden'
              && s.opacity !== '0' && el.offsetParent !== null;
          }

          function fillField(el, value) {
            if (!el || !value) return;
            el.focus();
            el.dispatchEvent(new Event('focus', { bubbles: true }));
            const setter = Object.getOwnPropertyDescriptor(
              window.HTMLInputElement.prototype, 'value'
            )?.set;
            if (setter) { setter.call(el, value); } else { el.value = value; }
            el.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
            el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
            el.dispatchEvent(new Event('blur', { bubbles: true }));
          }

          const pwFields = [...document.querySelectorAll('input[type="password"]')].filter(isVisible);
          if (pwFields.length === 0) return { success: false, error: 'no_password_field' };

          const pw = pwFields[0];
          const form = pw.closest('form') || document;
          const selectors = [
            'input[autocomplete="username"]', 'input[autocomplete="email"]',
            'input[name="login"]', 'input[name="username"]', 'input[name="email"]',
            'input[name="user"]', 'input[name="loginfmt"]',
            'input[id="login_field"]', 'input[id="identifierId"]',
            'input[id="okta-signin-username"]', 'input[id="email"]',
            'input[type="email"]',
            'input[type="text"]:not([autocomplete="off"])'
          ];
          let userField = null;
          for (const sel of selectors) {
            const c = [...form.querySelectorAll(sel)].filter(isVisible);
            if (c.length > 0) { userField = c[0]; break; }
          }

          fillField(userField, '\(escapedUser)');
          fillField(pw, '\(escapedPass)');
          return { success: true };
        })()
        """
    }
}
