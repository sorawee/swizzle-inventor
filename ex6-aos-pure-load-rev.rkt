#lang rosette

(require "util.rkt" "cuda.rkt" "cuda-synth.rkt")

(define struct-size 3)
(define n-block 1)

(define (create-IO warpSize)
  (set-warpSize warpSize)
  (define block-size (* 2 warpSize))
  (define array-size (* n-block block-size))
  (define I-sizes (x-y-z (* array-size struct-size)))
  (define I (create-matrix I-sizes gen-uid))
  (define O (create-matrix I-sizes))
  (define O* (create-matrix I-sizes))
  (values block-size I-sizes I O O*))

(define (run-with-warp-size spec kernel w)
  (define-values (block-size I-sizes I O O*)
  (create-IO w))

  (define c (gcd struct-size warpSize))
  (define a (/ struct-size c))
  (define b (/ warpSize c))

  (run-kernel spec (x-y-z block-size) (x-y-z n-block) I O a b c)
  (run-kernel kernel (x-y-z block-size) (x-y-z n-block) I O* a b c)
  (define ret (equal? O O*))
  ;(pretty-display `(O ,O))
  ;(pretty-display `(O* ,O*))
  ret
  )

(define (AOS-load-spec threadId blockID blockDim I O a b c)
  (define I-cached (create-matrix (x-y-z struct-size)))
  (define warpID (get-warpId threadId))
  (define offset (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))  ;; warpID = (threadIdy * blockDimx + threadIdx)/warpSize
  (define gid (get-global-threadId threadId blockID))
  (global-to-warp-reg I I-cached
                 (x-y-z 1)
                 offset (x-y-z (* warpSize struct-size)) #f)
  (warp-reg-to-global I-cached O
                      (x-y-z struct-size) offset (x-y-z (* warpSize struct-size)) #f)
  )

;; cpu time: 372563 real time: 3828661
(define (AOS-load-test3 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix (x-y-z struct-size)))
   (define O-cached
     (for/vector ((i blockSize)) (create-matrix (x-y-z struct-size))))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-warp-reg
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f)
   (define localId (get-idInWarp threadId))
   (for/bounded
    ((i struct-size))
    (let* ((index
            (modulo
             (quotient
              (+
               (+ (quotient localId (@dup a)) (* (@dup i) (@dup warpSize)))
               (* (* (@dup i) (@dup a)) (@dup b)))
              (@dup b))
             struct-size))
           (lane
            (-
             (-
              (- (* localId (@dup a)) (- (@dup i) localId))
              (- (* localId (@dup b)) (quotient localId (@dup c))))
             (+
              (- (modulo (@dup i) (@dup c)) (+ localId localId))
              (* (+ (@dup i) (@dup i)) (@dup struct-size)))))
           (x (shfl (get I-cached index) lane))
           (index-o (modulo (* (- (@dup i) localId) (@dup b)) struct-size)))
      (set O-cached index-o x)))
   (warp-reg-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f))

(define (AOS-load-sketch threadId blockID blockDim I O a b c)
  (define I-cached (create-matrix (x-y-z struct-size)))
  (define O-cached (for/vector ([i blockSize]) (create-matrix (x-y-z struct-size))))
  (define warpID (get-warpId threadId))
  (define offset (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))  ;; warpID = (threadIdy * blockDimx + threadIdx)/warpSize
  (define gid (get-global-threadId threadId blockID))
  (global-to-warp-reg I I-cached
                 (x-y-z 1)
                 offset
                 (x-y-z (* warpSize struct-size)) #f)

  (define localId (get-idInWarp threadId))
  (for/bounded ([i struct-size])
    (let* (;[index (modulo (?index localId (@dup i) [a b c struct-size warpSize] 4) struct-size)]  ; (?index localId (@dup i) 1)
           ;[lane (?lane localId (@dup i) [a b c struct-size warpSize] 4)]  ; (+ (modulo (+ i (quotient localId 2)) 2) (* localId 2))
           [index (modulo (?index localId (@dup i) [a b c struct-size warpSize] 2) struct-size)]
           [p (?lane localId (@dup i) [a b c struct-size warpSize] 2)]
           [q1 (?lane localId (@dup i) p [a b c struct-size warpSize] 4)]
           [q2 (?lane localId (@dup i) p q1 [a b c struct-size warpSize] 4)]
           [lane (?lane localId (@dup i) p q1 q2 [a b c struct-size warpSize] 1)]
           [x (shfl (get I-cached index) lane)]
           [index-o (modulo (?index localId (@dup i) [a b c struct-size warpSize] 3) struct-size)])
      (set O-cached index-o x))
      )
  
  (warp-reg-to-global O-cached O
                      (x-y-z 1)
                      offset
                      (x-y-z (* warpSize struct-size)) #f)
  )

(define (test)
  (for ([w (list 3 4 5 6)])
    (let ([ret (run-with-warp-size AOS-load-spec AOS-load-test3 w)])
      (pretty-display `(test ,w ,ret))))
  )
;(test)

(define (synthesis)
  (pretty-display "solving...")
  (define sol (time (solve (assert (andmap (lambda (w) (run-with-warp-size AOS-load-spec AOS-load-sketch w))
                                           (list 3 4 5 6))))))
  (print-forms sol)
  )
(synthesis)
