(use-modules (guix ci)
            (guix channels))

(define %guix-mirror-channel
  (channel
    (name 'guix)
    (url "https://github.com/Millak/guix")))

(define %nonguix-channel
  (channel
   (name 'nonguix)
   (url "https://gitlab.com/nonguix/nonguix")))

(append (list (channel-with-substitutes-available
              %guix-mirror-channel
              "https://ci.guix.gnu.org"))
        (list (channel-with-substitutes-available
              %nonguix-channel
              "https://ci.guix.gnu.org")))
