#lang rosette

(require "util.rkt" "cuda.rkt" "cuda-synth.rkt")

(define WARP_SIZE 32)
(define n-block (x-y-z 1 1))
(define /9 (lambda (x) (/ x 9)))
(define W 8)
(define H 4)
(define warp-shape (x-y-z W H))

(define (create-IO warpSize)
  (pretty-display `(warpSize ,warpSize))
  (set-warpSize warpSize)
  (define block-size (x-y-z (* 2 warpSize) 2))
  (define I-sizes (* 2 warp-shape))
  (define O-sizes (- I-sizes 2))
  (define I (create-matrix I-sizes gen-uid))
  (define O (create-matrix O-sizes))
  (define O* (create-matrix O-sizes))
  (values block-size I-sizes O-sizes I O O*))

(define (run-with-warp-size spec kernel w)
  (define-values (block-size I-sizes O-sizes I O O*)
    (create-IO w))

  (spec I O O-sizes)
  (run-kernel kernel block-size n-block I O* I-sizes O-sizes)
  (pretty-display ">>> O")
  (acc-print O)
  (pretty-display ">>> O*")
  (acc-print O*)
  (acc-equal? O O*)
  )

(define (conv2d-spec I O o-sizes)
  (for* ([j (get-y o-sizes)]
         [i (get-x o-sizes)])
    (let ([o (create-accumulator (list +) /9)])
      (for* ([jj 3] [ii 3])
        (accumulate o (get I (+ i ii) (+ j jj)))
      (set O i j o)))))

(define (conv2d threadId blockID blockDim I O I-sizes O-sizes)
  (define gid (+ (* blockID blockDim) threadId))
  (define gx (get-x gid))
  (define gy (get-y gid))
  (define id (modulo (get-x threadId) warpSize))
  (define warp-col (modulo id W))
  (define warp-row (quotient id W))

  (define offset-x (* (quotient gx warpSize) W))
  (define offset-y (* gy H))

  (define I-cached (create-matrix-local (x-y-z 2 2)))
  (global-to-local I I-cached
                 (x-y-z 1 1)
                 (lov2vol (x-y-z offset-x offset-y))
                 (+ warp-shape 2) #f
                 #:warp-shape warp-shape #:round (x-y-z 2 2))

  (define o (create-accumulator (list +) /9 blockDim))
  
  (for* ([ky 3] [kx 3])
    (let* ([index-j (ite (< warp-row ky) 1 0)]
           [index-i (ite (< warp-col kx) 1 0)]
           [lane-x (fan warp-col W 1 W W 1
                        kx 3 1 3)]
           [lane-y (fan warp-row H 1 H H 1
                        ky 3 1 3)]
           [lane (+ (* lane-y W) lane-x)]
           [x (shfl (get I-cached index-i index-j) lane)])
      (accumulate o x)
      ))
  (acc-print o)
  (reg-to-global (accumulate-final o) O
                 (lov2vol (x-y-z (+ offset-x warp-col) (+ offset-y warp-row))))
  )

(define (conv2d-sketch threadId blockID blockDim I O I-sizes O-sizes)
  (define gid (+ (* blockID blockDim) threadId))
  (define gx (get-x gid))
  (define gy (get-y gid))
  (define id (modulo (get-x threadId) warpSize))
  (define warp-col (modulo id W))
  (define warp-row (quotient id W))

  (define offset-x (* (quotient gx warpSize) W))
  (define offset-y (* gy H))

  (define I-cached (create-matrix-local (x-y-z 2 2)))
  (global-to-local I I-cached
                 (x-y-z 1 1)
                 (lov2vol (x-y-z offset-x offset-y))
                 (+ warp-shape 2) #f
                 #:warp-shape warp-shape #:round (x-y-z 2 2))

  (define o (create-accumulator (list +) /9 blockDim))
  
  (for* ([ky 3] [kx 3])
    (let* ([index-j (ite (?cond-easy warp-row ky) (@dup 0) (@dup 1))]
           [index-i (ite (?cond-easy warp-col kx) (@dup 0) (@dup 1))]
           [lane-x (?fan-easy warp-col W
                              kx 3 [] #:fw 1)]
           [lane-y (?fan-easy warp-row H
                              ky 3 [] #:fw 1)]
           [lane (+ (* lane-y W) lane-x)]
           [x (shfl (get I-cached index-i index-j) lane)])
      (accumulate o x)
      ))
  (acc-print o)
  (reg-to-global (accumulate-final o) O
                 (lov2vol (x-y-z (+ offset-x warp-col) (+ offset-y warp-row))))
  )

(define (test)
  (for ([w (list WARP_SIZE)])
    (let ([ret (run-with-warp-size conv2d-spec conv2d w)])
      (pretty-display `(test ,w ,ret))))
  )
;(test)


;; warp size 32, ?fan-easy: 
(define (synthesis)
  (pretty-display "solving...")
  (define sol
    (time (solve
           (assert (andmap
                    (lambda (w) (run-with-warp-size conv2d-spec conv2d-sketch w))
                    (list WARP_SIZE))))))
  (print-forms sol)
  ;(print-lane 'lane (evaluate my-lane sol) '#(localId i) '#())
  )
(synthesis)