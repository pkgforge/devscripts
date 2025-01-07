;; SELF: https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/nonguix.channels.scm
;; ADD: curl -qfsSL "https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Linux/nonguix.channels.scm" | sudo tee "/root/.config/guix/channels.scm"
;; PULL: sudo GIT_CONFIG_PARAMETERS="'filter.blob:none.enabled=true'" guix pull --cores="$(($(nproc)+1))" --max-jobs="$(($(nproc)+1))"
(use-modules (guix ci))

;; Define %default-guix-channel with substitutes available
(define guix-ci-substitutes
  (channel-with-substitutes-available
   %default-guix-channel
   "https://ci.guix.gnu.org"))

;; Add nonguix channel
(define nonguix-channel
  (channel
   (name 'nonguix)
   (url "https://gitlab.com/nonguix/nonguix")
   ;; Enable signature verification:
   (introduction
    (make-channel-introduction
     "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
     (openpgp-fingerprint
      "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5")))))

;; Combine channels
(list guix-ci-substitutes nonguix-channel)
