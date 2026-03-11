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

      // Scan on load and on DOM mutations (for multi-step login flows)
      scan();
      const observer = new MutationObserver(() => { scan(); });
      observer.observe(document.body || document.documentElement, {
        childList: true, subtree: true
      });
    })()
    """

    /// Returns JS that fills a login form with the given credentials.
    /// Uses native setter bypass for React/Vue/Angular compatibility.
    static func fillScript(username: String, password: String) -> String {
        let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

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
