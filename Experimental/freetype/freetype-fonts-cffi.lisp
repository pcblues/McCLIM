;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: MCCLIM-FREETYPE; -*-
;;; ---------------------------------------------------------------------------
;;;     Title: Experimental FreeType support
;;;   Created: 2003-05-25 16:32
;;;    Author: Gilbert Baumann <unk6@rz.uni-karlsruhe.de>
;;;   License: LGPL (See file COPYING for details).
;;; ---------------------------------------------------------------------------
;;;  (c) copyright 2003 by Gilbert Baumann

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the 
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330, 
;;; Boston, MA  02111-1307  USA.

(in-package :MCCLIM-FREETYPE)

;;; reset safety up to 3 to try to work out some of my problems.  If
;;; this gets fixed, presumably it should be dropped back down to
;;; 1... [2006/05/24:rpg]
(declaim (optimize (speed 3) (safety 3) (debug 3) (space 3)))

;;;; Notes

;; You might need to tweak mcclim-freetype::*families/faces* to point
;; to where ever there are suitable TTF fonts on your system.

(defclass vague-font ()
  ((lib :initarg :lib)
   (filename :initarg :filename)))

(defparameter *vague-font-hash* (make-hash-table :test #'equal))

(defun make-vague-font (filename)
  (let ((val (gethash filename *vague-font-hash*)))
    (or val
        (setf (gethash filename *vague-font-hash*)
	      (make-instance 'vague-font
		:lib
		;; I am not at all sure that this is the
		;; right translation --- because of the
		;; difference between SBCL aliens and
		;; CFFI, I'm not sure what the deref was
		;; intended to achieve... [2006/05/24:rpg]
		(let ((libf (cffi:foreign-alloc 'freetype:library)))
		  (freetype:init-free-type libf)
		  (cffi:mem-aref libf 'freetype:library))
;;;			     (let ((libf (make-alien freetype:library)))
;;;                                    (declare (type (alien (* freetype:library)) libf))
;;;                                    (freetype:init-free-type libf)
;;;                                    (deref libf))
		:filename filename)))))

(defparameter *dpi* 72)

(defparameter *concrete-font-hash* (make-hash-table :test #'equal))

(defun make-concrete-font (vague-font size &key (dpi *dpi*))
  (with-slots (lib filename) vague-font
    (let* ((key (cons lib filename))
           (val (gethash key *concrete-font-hash*)))
      (unless val
        (let ((facef
	       ;; this will allocate a pointer (notionally to a
	       ;; face-rec), and return a pointer to it (the pointer).
	       (foreign-alloc 'freetype:face)
	       ;;(make-alien freetype:face))
	      ))
          ;;(declare (type (alien (* freetype:face)) facef))
          (if (zerop (freetype:new-face lib filename 0 facef))
              (setf val (setf (gethash key *concrete-font-hash*)
			      (cffi:mem-ref facef 'freetype:face)))
	      
;;;	      (setf val (setf (gethash key *concrete-font-hash*)
;;;                              (deref facef)))
              (error "Freetype error in make-concrete-font"))))
      (let ((face val))
        ;; (declare (type (alien freetype:face) face))
        (freetype:set-char-size face 0 (round (* size 64)) (round dpi) (round dpi))
        face))))

(declaim (inline make-concrete-font))

(defun glyph-pixarray (face char)
;;;  (declare (optimize (speed 3) (debug 1))
;;;           (inline freetype:load-glyph freetype:render-glyph)
;;;           (type (alien freetype:face) face))
  (freetype:load-glyph face (freetype:get-char-index face (char-code char)) 0)
  (freetype:render-glyph (foreign-slot-value face 'freetype:face-rec 'freetype:glyph) 0)
  (with-foreign-slots ((glyph) face freetype:face-rec)
    (with-foreign-slots ((bitmap) glyph freetype:glyph-slot-rec)
      (with-foreign-slots ((width pitch rows buffer) bitmap freetype:bitmap)
	(let ((res
	       (make-array (list rows width)
			   :element-type '(unsigned-byte 8))))
;;;    (let* ((width  (slot bm 'freetype:width))
;;;           (pitch  (slot bm 'freetype:pitch))
;;;           (height (slot bm 'freetype:rows))
;;;           (buffer (slot bm 'freetype:buffer))
;;;           (res    (make-array (list height width) :element-type '(unsigned-byte 8))))
	  (declare (type (simple-array (unsigned-byte 8) (* *)) res))
	  (let ((m (* width rows)))
	    (locally
		(declare (optimize (speed 3) (safety 0)))
	      (loop for y*width of-type fixnum below m by width 
		  for y*pitch of-type fixnum from 0 by pitch do
		    (loop for x of-type fixnum below width do
			  (setf (row-major-aref res (+ x y*width))
				(cffi:mem-aref buffer :uint8 (+ x y*pitch))
			    ;; (deref buffer (+ x y*pitch))
				)))))
	  (with-foreign-slots ((bitmap-left
				bitmap-top
				advance) glyph freetype:glyph-slot-rec)
	    (with-foreign-slots ((x y) advance freetype:vector)
	      (values
	       res
	       bitmap-left
	       ;; (slot glyph 'freetype:bitmap-left)
	       bitmap-top
	       ;;(slot glyph 'freetype:bitmap-top)
	       (/ x 64)
	       ;;(/ (slot (slot glyph 'freetype:advance) 'freetype:x) 64)
	       (/ y 64)
	       ;;(/ (slot (slot glyph 'freetype:advance) 'freetype:y) 64)
	       )
	      )))))))

(defun glyph-advance (face char)
  ;; I believe that face is a pointer to a face-rec...
  ;; note that we're not catching error result here...
  (freetype:load-glyph face (freetype:get-char-index face (char-code char)) 0)
  (let* ((glyph (foreign-slot-value face 'freetype:face-rec 'freetype:glyph)))
    ;;; glyph will be a glyph-slot-rec...
    (with-foreign-slots ((advance) glyph freetype:glyph-slot-rec)
      (with-foreign-slots ((x y) advance freetype:vector)
	(values
	 (/ x 64)
	 (/ y 64))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun display-glyph-cache (display)
  (or (getf (xlib:display-plist display) 'glyph-cache)
      (setf (getf (xlib:display-plist display) 'glyph-cache)
            (make-hash-table :test #'equalp))))

(defun display-the-glyph-set (display)
  (or (getf (xlib:display-plist display) 'the-glyph-set)
      (setf (getf (xlib:display-plist display) 'the-glyph-set)
            (xlib::render-create-glyph-set
             (first (xlib::find-matching-picture-formats display
                                                         :alpha 8 :red 0 :green 0 :blue 0))))))

(defun display-free-glyph-ids (display)
  (getf (xlib:display-plist display) 'free-glyph-ids))

(defun (setf display-free-glyph-ids) (new-value display)
  (setf (getf (xlib:display-plist display) 'free-glyph-ids) new-value))

(defun display-free-glyph-id-counter (display)
  (getf (xlib:display-plist display) 'free-glyph-id-counter 0))

(defun (setf display-free-glyph-id-counter) (new-value display)
  (setf (getf (xlib:display-plist display) 'free-glyph-id-counter) new-value))

(defun display-draw-glyph-id (display)
  (or (pop (display-free-glyph-ids display))
      (incf (display-free-glyph-id-counter display))))

(defun display-get-glyph (display font matrix glyph-index)
  (or (gethash (list font matrix glyph-index) (display-glyph-cache display))
      (setf (gethash (list font matrix glyph-index) (display-glyph-cache display))
            (display-generate-glyph display font matrix glyph-index))))

(defvar *font-hash*
  (make-hash-table :test #'equalp))

(defun display-generate-glyph (display font matrix glyph-index)
  (let* ((glyph-id (display-draw-glyph-id display))
         (font (or (gethash font *font-hash*)
		   (setf (gethash font *font-hash*)
			 (make-vague-font font))))
         (face (make-concrete-font font matrix)))
    (multiple-value-bind (arr left top dx dy) (glyph-pixarray face (code-char glyph-index))
      (when (= (array-dimension arr 0) 0)
        (setf arr (make-array (list 1 1) :element-type '(unsigned-byte 8) :initial-element 0)))
      (xlib::render-add-glyph (display-the-glyph-set display) glyph-id
                              :data arr
                              :x-origin (- left)
                              :y-origin top
                              :x-advance dx
                              :y-advance dy)
      (let ((right (+ left (array-dimension arr 1))))
        (list glyph-id dx dy left right top)))))

;;;;;;; mcclim interface

(defclass freetype-face ()
  ((display :initarg :display)
   (font :initarg :font)
   (matrix :initarg :matrix)
   (ascent :initarg :ascent)
   (descent :initarg :descent)))

(defmethod clim-clx::font-ascent ((font freetype-face))
  (with-slots (ascent) font
    ascent))

(defmethod clim-clx::font-descent ((font freetype-face))
  (with-slots (descent) font
    descent))

(defmethod clim-clx::font-glyph-width ((font freetype-face) char)
  (with-slots (display font matrix) font
    (nth 1 (display-get-glyph display font matrix char))))
(defmethod clim-clx::font-glyph-left ((font freetype-face) char)
  (with-slots (display font matrix) font
    (nth 3 (display-get-glyph display font matrix char))))
(defmethod clim-clx::font-glyph-right ((font freetype-face) char)
  (with-slots (display font matrix) font
    (nth 4 (display-get-glyph display font matrix char))))

;;; this is a hacky copy of XLIB:TEXT-EXTENTS
(defmethod clim-clx::font-text-extents ((font freetype-face) string
                                        &key (start 0) (end (length string)) translate)
  ;; -> (width ascent descent left right
  ;; font-ascent font-descent direction
  ;; first-not-done)
  translate
  (let ((width (loop for i from start below end 
                     sum (clim-clx::font-glyph-width font (char-code (aref string i))))))
    (values
     width
     (clim-clx::font-ascent font)
     (clim-clx::font-descent font)
     (clim-clx::font-glyph-left font (char-code (char string start)))
     (- width (- (clim-clx::font-glyph-width font (char-code (char string (1- end))))
                 (clim-clx::font-glyph-right font (char-code (char string (1- end))))))
     (clim-clx::font-ascent font)
     (clim-clx::font-descent font)
     0 end)))

(defun drawable-picture (drawable)
  (or (getf (xlib:drawable-plist drawable) 'picture)
      (setf (getf (xlib:drawable-plist drawable) 'picture)
            (xlib::render-create-picture drawable
                                         :format
                                         (xlib::find-window-picture-format
                                          (xlib:drawable-root drawable))))))

(defun gcontext-picture (drawable gcontext)
  (or (getf (xlib:gcontext-plist gcontext) 'picture)
      (setf (getf (xlib:gcontext-plist gcontext) 'picture)
            (let ((pixmap (xlib:create-pixmap :drawable drawable
                           :depth (xlib:drawable-depth drawable)
                           :width 1 :height 1)))
              (list
               (xlib::render-create-picture
                pixmap
                :format (xlib::find-window-picture-format (xlib:drawable-root drawable))
                :repeat :on)
               pixmap)))))

(defmethod clim-clx::font-draw-glyphs ((font freetype-face) mirror gc x y string &key start end translate)
  (declare (ignore translate))
  (let ((display (xlib:drawable-display mirror)))
    (with-slots (font matrix) font
      (destructuring-bind (source-picture source-pixmap)
	  (gcontext-picture mirror gc)
	(declare (ignore source-pixmap))
        (let ((fg (xlib:gcontext-foreground gc)))
          (xlib::render-fill-rectangle source-picture
                                       :src
                                       (list (ash (ldb (byte 8 16) fg) 8)
                                             (ash (ldb (byte 8 8) fg) 8)
                                             (ash (ldb (byte 8 0) fg) 8)
                                             #xFFFF)
                                       0 0 1 1))
        (setf (xlib::picture-clip-mask (drawable-picture mirror))
              (xlib::gcontext-clip-mask gc))
        (xlib::render-composite-glyphs
         (drawable-picture mirror)
         (display-the-glyph-set display)
         source-picture
         x y
         (map 'vector (lambda (x)
                        (first
                         (display-get-glyph display font matrix (char-code x))))
              (subseq string start end)))))))

(let ((cache (make-hash-table :test #'equal)))
  (defun make-free-type-face (display font size)
    (or (gethash (list display font size) cache)
        (setf (gethash (list display font size) cache)
	  (let* ((f.font (or (gethash font *font-hash*)
			     (setf (gethash font *font-hash*)
			       (make-vague-font font))))
		 (f (make-concrete-font f.font size)))
	    (with-foreign-slots ((size_s) f freetype:face-rec)
	      (with-foreign-slots ((metrics) size_s freetype:size-rec)
		(with-foreign-slots ((ascender descender) metrics freetype:size-metrics)
		  (make-instance 'freetype-face
		    :display display
		    :font font
		    :matrix size
		    :ascent  (/ ascender 64)
		    :descent (/ descender -64))))))))))

(defparameter *sizes*
  '(:normal 12
    :small 10
    :very-small 8
    :tiny 8
    :large 14
    :very-large 18
    :huge 24))

(defparameter *families/faces*
  '(((:fix :roman) . "VeraMono.ttf")
    ((:fix :italic) . "VeraMoIt.ttf")
    ((:fix (:bold :italic)) . "VeraMoBI.ttf")
    ((:fix (:italic :bold)) . "VeraMoBI.ttf")
    ((:fix :bold) . "VeraMoBd.ttf")
    ((:serif :roman) . "VeraSe.ttf")
    ((:serif :italic) . "VeraSe.ttf")
    ((:serif (:bold :italic)) . "VeraSeBd.ttf")
    ((:serif (:italic :bold)) . "VeraSeBd.ttf")
    ((:serif :bold) . "VeraSeBd.ttf")
    ((:sans-serif :roman) . "Vera.ttf")
    ((:sans-serif :italic) . "VeraIt.ttf")
    ((:sans-serif (:bold :italic)) . "VeraBI.ttf")
    ((:sans-serif (:italic :bold)) . "VeraBI.ttf")
    ((:sans-serif :bold) . "VeraBd.ttf")))

(defvar *freetype-font-path*)

(fmakunbound 'clim-clx::text-style-to-x-font)

(defstruct freetype-device-font-name
  (font-file (error "missing argument"))
  (size (error "missing argument")))

(defmethod clim-clx::text-style-to-X-font :around 
    ((port clim-clx::clx-port) (text-style climi::device-font-text-style))
  (let ((display (slot-value port 'clim-clx::display))
        (font-name (climi::device-font-name text-style)))
    (make-free-type-face display
                         (freetype-device-font-name-font-file font-name)
                         (freetype-device-font-name-size font-name))))

(defmethod text-style-mapping :around
    ((port clim-clx::clx-port) (text-style climi::device-font-text-style)
     &optional character-set)
  (declare (ignore character-set))
  (values (gethash text-style (clim-clx::port-text-style-mappings port))))

(defmethod (setf text-style-mapping) :around
    (value 
     (port clim-clx::clx-port) 
     (text-style climi::device-font-text-style)
     &optional character-set)
  (declare (ignore character-set))
  (setf (gethash text-style (clim-clx::port-text-style-mappings port)) value))

(defparameter *free-type-face-hash* (make-hash-table :test #'equal))

(defmethod clim-clx::text-style-to-X-font :around ((port clim-clx::clx-port) (text-style standard-text-style))
  (multiple-value-bind (family face size) 
      (clim:text-style-components text-style)
    (let ((display (clim-clx::clx-port-display port)))
      (setf face (or face :roman))
      (setf size (or size :normal))
      (cond (size
	     (setf size (getf *sizes* size size))
	     (let ((val (gethash (list display family face size) *free-type-face-hash*)))
	       (if val val
		   (setf (gethash (list display family face size) *free-type-face-hash*)
			 (let* ((font-path-relative (cdr (assoc (list family face) *families/faces*
								:test #'equal)))
				(font-path (namestring (merge-pathnames font-path-relative *freetype-font-path*))))
			   (if (and font-path (probe-file font-path))
			       (make-free-type-face display font-path size)
			       (call-next-method)))))))
	    (t
	     (call-next-method))))))

(defmethod clim-clx::text-style-to-X-font ((port clim-clx::clx-port) text-style)
  ;; ok, this isn't the most helpful error message... [2006/05/24:rpg]
  (error "You lost: ~S." text-style))

;;;;;;

(in-package :clim-clx)

(defmethod text-style-ascent (text-style (medium clx-medium))
  (let ((font (text-style-to-X-font (port medium) text-style)))
    (clim-clx::font-ascent font)))

(defmethod text-style-descent (text-style (medium clx-medium))
  (let ((font (text-style-to-X-font (port medium) text-style)))
    (clim-clx::font-descent font)))

(defmethod text-style-height (text-style (medium clx-medium))
  (let ((font (text-style-to-X-font (port medium) text-style)))
    (+ (clim-clx::font-ascent font) (clim-clx::font-descent font))))

(defmethod text-style-character-width (text-style (medium clx-medium) char)
  (clim-clx::font-glyph-width (text-style-to-X-font (port medium) text-style) (char-code char)))

(defmethod text-style-width (text-style (medium clx-medium))
  (text-style-character-width text-style medium #\m))

(defmethod text-size ((medium clx-medium) string &key text-style (start 0) end)
  (when (characterp string)
    (setf string (make-string 1 :initial-element string)))
  (unless end (setf end (length string)))
  (unless text-style (setf text-style (medium-text-style medium)))
  (let ((xfont (text-style-to-X-font (port medium) text-style)))
    (cond ((= start end)
           (values 0 0 0 0 0))
          (t
           (let ((position-newline (position #\newline string :start start)))
             (cond ((not (null position-newline))
                    (multiple-value-bind (width ascent descent left right
                                                font-ascent font-descent direction
                                                first-not-done)
                        (font-text-extents xfont string
                                           :start start :end position-newline
                                           :translate #'translate)
                      (declare (ignorable left right
                                          font-ascent font-descent
                                          direction first-not-done))
                      (multiple-value-bind (w h x y baseline)
                          (text-size medium string :text-style text-style
                                     :start (1+ position-newline) :end end)
                        (values (max w width) (+ ascent descent h)
                                x (+ ascent descent y) (+ ascent descent baseline)))))
                   (t
                    (multiple-value-bind (width ascent descent left right
                                                font-ascent font-descent direction
                                                first-not-done)
                        (font-text-extents xfont string
                                   :start start :end end
                                   :translate #'translate)
                      (declare (ignorable left right
                                          font-ascent font-descent
                                          direction first-not-done))
                      (values width (+ ascent descent) width 0 ascent)) )))))) )

(defmethod climi::text-bounding-rectangle*
    ((medium clx-medium) string &key text-style (start 0) end)
  (when (characterp string)
    (setf string (make-string 1 :initial-element string)))
  (unless end (setf end (length string)))
  (unless text-style (setf text-style (medium-text-style medium)))
  (let ((xfont (text-style-to-X-font (port medium) text-style)))
    (cond ((= start end)
           (values 0 0 0 0))
          (t
           (let ((position-newline (position #\newline string :start start)))
             (cond ((not (null position-newline))
                    (multiple-value-bind (width ascent descent left right
                                                font-ascent font-descent direction
                                                first-not-done)
                        (font-text-extents xfont string
                                           :start start :end position-newline
                                           :translate #'translate)
                      (declare (ignorable left right
                                          font-ascent font-descent
                                          direction first-not-done)
			       (ignore width))
                      (multiple-value-bind (minx miny maxx maxy)
                          (climi::text-bounding-rectangle*
                           medium string :text-style text-style
                           :start (1+ position-newline) :end end)
			(declare (ignore miny))
                        (values (min minx left) (- ascent)
                                (max maxx right) (+ descent maxy)))))
                   (t
                    (multiple-value-bind (width ascent descent left right
                                                font-ascent font-descent direction
                                                first-not-done)
                        (font-text-extents xfont string
                                   :start start :end end
                                   :translate #'translate)
                      (declare (ignore width direction first-not-done
				       descent ascent))
                      ;; FIXME: Potential style points:
                      ;; * (min 0 left), (max width right)
                      ;; * font-ascent / ascent
                      (values left (- font-ascent) right font-descent)))))))))


(defmethod make-medium-gcontext* (medium foreground background line-style text-style (ink color) clipping-region)
  (declare (ignore clipping-region line-style background foreground))
  (let* ((drawable (sheet-mirror (medium-sheet medium)))
         (port (port medium)))
    (let ((gc (xlib:create-gcontext :drawable drawable)))
      (Let ((fn (text-style-to-X-font port text-style)))
        (if (typep fn 'xlib:font)
            (setf (xlib:gcontext-font gc) fn)))
      (setf 
            (xlib:gcontext-foreground gc) (X-pixel port ink)
            )
      gc)))

(defmethod medium-draw-text* ((medium clx-medium) string x y
                              start end
                              align-x align-y
                              toward-x toward-y transform-glyphs)
  (declare (ignore toward-x toward-y transform-glyphs))
  (with-transformed-position ((sheet-native-transformation (medium-sheet medium))
                              x y)
    (with-clx-graphics (medium)
      (when (characterp string)
        (setq string (make-string 1 :initial-element string)))
      (when (null end) (setq end (length string)))
      (multiple-value-bind (text-width text-height x-cursor y-cursor baseline) 
          (text-size medium string :start start :end end)
        (declare (ignore x-cursor y-cursor))
        (unless (and (eq align-x :left) (eq align-y :baseline))	    
          (setq x (- x (ecase align-x
                         (:left 0)
                         (:center (round text-width 2))
                         (:right text-width))))
          (setq y (ecase align-y
                    (:top (+ y baseline))
                    (:center (+ y baseline (- (floor text-height 2))))
                    (:baseline y)
                    (:bottom (+ y baseline (- text-height)))))))
      (let ((x (round-coordinate x))
            (y (round-coordinate y)))
        (when (and (<= #x-8000 x #x7FFF)
                   (<= #x-8000 y #x7FFF))
          (multiple-value-bind (halt width)
              (font-draw-glyphs
               (text-style-to-X-font (port medium) (medium-text-style medium))
               mirror gc x y string
                                :start start :end end
                                :translate #'translate)))))))


(defmethod (setf medium-text-style) :before (text-style (medium clx-medium))
  (with-slots (gc) medium
    (when gc
      (let ((old-text-style (medium-text-style medium)))
	(unless (eq text-style old-text-style)
          (let ((fn (text-style-to-X-font (port medium) (medium-text-style medium))))
            (when (typep fn 'xlib:font)
              (setf (xlib:gcontext-font gc)
                    fn))))))))

(defmethod medium-gcontext ((medium clx-medium) (ink color))
  (let* ((port (port medium))
	 (mirror (port-lookup-mirror port (medium-sheet medium)))
	 (line-style (medium-line-style medium)))
    (with-slots (gc) medium
      (unless gc
	(setq gc (xlib:create-gcontext :drawable mirror))
	;; this is kind of false, since the :unit should be taken
	;; into account -RS 2001-08-24
	(setf (xlib:gcontext-line-width gc) (line-style-thickness line-style)
	      (xlib:gcontext-cap-style gc) (line-style-cap-shape line-style)
	      (xlib:gcontext-join-style gc) (line-style-joint-shape line-style))
	(let ((dashes (line-style-dashes line-style)))
	  (unless (null dashes)
	    (setf (xlib:gcontext-line-style gc) :dash
		  (xlib:gcontext-dashes gc) (if (eq dashes t) 3
						dashes)))))
      (setf (xlib:gcontext-function gc) boole-1)
      (let ((fn (text-style-to-X-font port (medium-text-style medium))))
        (when (typep fn 'xlib:font)
          (setf (xlib:gcontext-font gc) fn)))
      (setf (xlib:gcontext-foreground gc) (X-pixel port ink)
	    (xlib:gcontext-background gc) (X-pixel port (medium-background medium)))
      ;; Here is a bug with regard to clipping ... ;-( --GB )
      #-nil ; being fixed at the moment, a bit twitchy though -- BTS
      (let ((clipping-region (medium-device-region medium)))
        (if (region-equal clipping-region +nowhere+)
	    (setf (xlib:gcontext-clip-mask gc) #())
	    (let ((rect-seq (clipping-region->rect-seq clipping-region)))
	      (when rect-seq
		#+nil
		;; ok, what McCLIM is generating is not :yx-banded...
		;; (currently at least)
		(setf (xlib:gcontext-clip-mask gc :yx-banded) rect-seq)
		#-nil
		;; the region code doesn't support yx-banding...
		;; or does it? what does y-banding mean in this implementation?
		;; well, apparantly it doesn't mean what y-sorted means
		;; to clx :] we stick with :unsorted until that can be sorted out
		(setf (xlib:gcontext-clip-mask gc :unsorted) rect-seq)))))
      gc)))

;;;
;;; This fixes the worst offenders making the assumption that drawing
;;; would be idempotent.
;;;

(defmethod clim:handle-repaint :around ((s clim:sheet-with-medium-mixin) r)
  (let ((m (clim:sheet-medium s))
        (r (clim:bounding-rectangle
            (clim:region-intersection r (clim:sheet-region s)))))
    (unless (eql r clim:+nowhere+)
      (clim:with-drawing-options (m :clipping-region r)
        (clim:draw-design m r :ink clim:+background-ink+)
        (call-next-method s r)))))


;;;---------------------------------------------------------------------------
;;; compiler warnings
;;;---------------------------------------------------------------------------
#|
; While compiling (METHOD CLIM-INTERNALS::TEXT-BOUNDING-RECTANGLE* (CLX-MEDIUM T)):
Warning: Variable MINY is never used.
Warning: Variable WIDTH is never used.
; While compiling (METHOD MAKE-MEDIUM-GCONTEXT* (T T T T T COLOR T)):
Warning: Variable CLIPPING-REGION is never used.
Warning: Variable LINE-STYLE is never used.
Warning: Variable BACKGROUND is never used.
Warning: Variable FOREGROUND is never used.
; While compiling (METHOD MEDIUM-DRAW-TEXT* (CLX-MEDIUM T T T T T T T T T T)):
Warning: Variable WIDTH is never used.
Warning: Variable HALT is never used.
|#