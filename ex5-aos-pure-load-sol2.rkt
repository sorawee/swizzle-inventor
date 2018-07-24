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
  (pretty-display `(O ,(print-vec O)))
  (pretty-display `(O* ,(print-vec O*)))
  ret)

(define (AOS-load-spec threadId blockID blockDim I O a b c)
  (define I-cached (create-matrix-local (x-y-z struct-size)))
  (define warpID (get-warpId threadId))
  (define offset (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))  ;; warpID = (threadIdy * blockDimx + threadIdx)/warpSize
  (define gid (get-global-threadId threadId blockID))
  (global-to-local I I-cached
                 (x-y-z struct-size)
                 offset (x-y-z (* warpSize struct-size)) #f)
  (local-to-global I-cached O
                      (x-y-z 1) offset (x-y-z (* warpSize struct-size)) #f #:round struct-size)
  )

(define (print-vec x)
  (format "#(~a)" (string-join (for/list ([xi x]) (format "~a" xi)))))

(define (AOS-load2 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size) #:round struct-size)
    #f)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 0 1 2 1 localId warpSize 0 1))
           (lane (fan localId warpSize 2 16 32 -1 i struct-size 0 1))
           (x (shfl (get I-cached index) lane))
           (index-o (fan i struct-size 0 1 2 1 localId warpSize 0 16)))
      (unique-warp (modulo lane warpSize))
      (vector-set! indices i index)
      (vector-set! indices-o i index-o)
      (set O-cached index-o x)))
   (for
    ((t blockSize))
    (let ((l
           (for/list ((i struct-size)) (vector-ref (vector-ref indices i) t)))
          (lo
           (for/list
            ((i struct-size))
            (vector-ref (vector-ref indices-o i) t))))
      (unique-list l)
      (unique-list lo)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-loadsh2 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define temp (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((lane1 (fan localId warpSize 0 1 2 1 i struct-size 0 1))
           (x (shfl (get I-cached (@dup i)) lane1)))
      (set temp (@dup i) x)))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 0 1 2 1 localId warpSize 0 1))
           (lane2 (fan localId warpSize 16 2 32 1 i struct-size 15 1))
           (x (shfl-send (get temp index) lane2)))
      (set O-cached (@dup i) x)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-load3 threadId blockID blockDim I O a b c)
  (define I-cached (create-matrix-local (x-y-z struct-size)))
  (define O-cached (create-matrix-local (x-y-z struct-size)))
  (define localId (modulo (get-x threadId) 32))
  (define offset (* struct-size (- (+ (* blockID blockDim) (get-x threadId)) localId)))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 2 3 3 1 localId warpSize 0 1))
           (lane (fan localId warpSize 3 32 32 1 i struct-size 0 1))
           (x (shfl (get I-cached index) lane))
           (index-o (fan i struct-size 1 3 3 1 localId warpSize 0 warpSize)))
      (unique-warp (modulo lane warpSize))
      (set O-cached index-o x)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-loadhsh3 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define temp (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((lane1 (fan localId warpSize 0 1 32 1 i struct-size 31 1))
           (x (shfl (get I-cached (@dup i)) lane1)))
      (set temp (@dup i) x)))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 2 3 3 1 localId warpSize 0 1))
           (lane2 (fan localId warpSize 11 32 32 1 i struct-size 20 1))
           (x (shfl-send (get temp index) lane2)))
      (set O-cached (@dup i) x)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-loadhsh3* threadId blockID blockDim I O a b c)
  (define I-cached (create-matrix-local (x-y-z struct-size)))
  (define warpID (get-warpId threadId))
  (define offset
    (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
  (define gid (get-global-threadId threadId blockID))
  (global-to-local
   I
   I-cached
   (x-y-z 1)
   offset
   (x-y-z (* warpSize struct-size))
   #f #:round struct-size
   #:shfl (lambda (localId i) (fan localId warpSize 0 1 32 1 i struct-size 31 1)))
  (define localId (get-idInWarp threadId))
  (define O-cached (permute-vector I-cached struct-size
                                   (lambda (i) (fan i struct-size 2 3 3 1 localId warpSize 0 1))))
  (local-to-global
   O-cached
   O
   (x-y-z 1)
   offset
   (x-y-z (* warpSize struct-size))
   #f #:round struct-size
   #:shfl (lambda (localId i)
            (fan localId warpSize 11 32 32 1 i struct-size 20 1)))
  )

(define (AOS-load4 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 3 4 4 1 localId warpSize 0 1))
           (lane (fan localId warpSize 4 8 32 -1
                      i struct-size 0 1))
           (x (shfl (get I-cached index) lane))
           (index-o (fan i struct-size 0 1 4 1 localId warpSize 0 8)))
      (pretty-display `(lane ,lane))
      (unique-warp (modulo lane warpSize))
      (vector-set! indices i index)
      (vector-set! indices-o i index-o)
      (set O-cached index-o x)))
   (for
    ((t blockSize))
    (let ((l
           (for/list ((i struct-size)) (vector-ref (vector-ref indices i) t)))
          (lo
           (for/list
            ((i struct-size))
            (vector-ref (vector-ref indices-o i) t))))
      (unique-list l)
      (unique-list lo)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-loadsh4 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define temp (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((lane1 (fan localId warpSize 0 1 4 1 i struct-size 0 1))
           (x (shfl (get I-cached (@dup i)) lane1)))
      (set temp (@dup i) x)))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 0 1 4 1 localId warpSize 0 -1))
           (lane2 (fan localId warpSize 24 4 32 1 i struct-size 7 1))
           (x (shfl-send (get temp index) lane2)))
      (set O-cached (@dup i) x)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-load5 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((index (fan i struct-size 3 5 5 1 localId warpSize 1 1))
           (lane (fan localId warpSize 5 32 32 1 i struct-size 0 1))
           (x (shfl (get I-cached index) lane))
           (index-o (fan i struct-size 1 5 5 -1 localId warpSize 0 1)))
      (unique-warp (modulo lane warpSize))
      (vector-set! indices i index)
      (vector-set! indices-o i index-o)
      (set O-cached index-o x)))
   (for
    ((t blockSize))
    (let ((l
           (for/list ((i struct-size)) (vector-ref (vector-ref indices i) t)))
          (lo
           (for/list
            ((i struct-size))
            (vector-ref (vector-ref indices-o i) t))))
      (unique-list l)
      (unique-list lo)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (AOS-loadsh5 threadId blockID blockDim I O a b c)
   (define I-cached (create-matrix-local (x-y-z struct-size)))
   (define temp (create-matrix-local (x-y-z struct-size)))
   (define O-cached (create-matrix-local (x-y-z struct-size)))
   (define warpID (get-warpId threadId))
   (define offset
     (+ (* struct-size blockID blockDim) (* struct-size warpID warpSize)))
   (define gid (get-global-threadId threadId blockID))
   (global-to-local
    I
    I-cached
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size)
   (define indices (make-vector struct-size))
   (define indices-o (make-vector struct-size))
   (define localId (get-idInWarp threadId))
   (for
    ((i struct-size))
    (let* ((x (get I-cached (@dup i))))
      (set temp (@dup i) x)))
   (for
    ((i struct-size))
    (let* ((index (fan i 5 3 5 5 1
                       localId warpSize 2 warpSize))
           #;(index
            (modulo (+ (* 3 i) (* localId 2)) 5))
           (lane2 (fan localId 32 13 32 32 1
                       i 5 19 5))
           #;(lane2
            (modulo
             (- (* 13 localId) (* 13 i))
             32))
           (x (shfl-send (get temp index) lane2)))
      ;(pretty-display `(lane ,(print-vec (modulo lane2 32))))
      (set O-cached (@dup i) x)))
   (local-to-global
    O-cached
    O
    (x-y-z 1)
    offset
    (x-y-z (* warpSize struct-size))
    #f #:round struct-size))

(define (test)
  (for ([w (list 32)])
    (let ([ret (run-with-warp-size AOS-load-spec AOS-load3 w)])
      (pretty-display `(test ,w ,ret))))
  )
(test)