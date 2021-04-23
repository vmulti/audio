// Copyright (c) 2020-2021 spaceface, spytheman, henrixounez. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module audio

import math
import sokol.audio as saudio

const (
	tau    = 2 * math.pi
	transi = 500
)

[inline]
fn midi2freq(midi byte) f32 {
	return int(math.powf(2, f32(midi - 69) / 12) * 440)
}

pub struct Note {
mut:
	freq   f32
	vol    f32
	step   u32
	paused bool
}

type NextFn = fn (freq f32, time f32, amp f32) f32

[inline]
fn square(freq f32, time f32, amp f32) f32 {
	t := time * freq
	f := t - int(t)
	return if f < 0.5 { amp / 2  } else { -amp / 2 }
}

// pure triangle wave
[inline]
fn triangle(freq f32, time f32, amp f32) f32 {
	t := time * freq
	f := t - int(t)
	return f32(2 * math.abs(2 * (f - 0.5)) - 1) * amp
}

// pure sawtooth wave
[inline]
fn sawtooth(freq f32, time f32, amp f32) f32 {
	t := time * freq
	f := t - int(t)
	return f32(2 * (f - 0.5)) * amp / 2
}

// pure sine wave
[inline]
fn sine(freq f32, time f32, amp f32) f32 {
	return math.sinf(audio.tau * time * freq) * amp
}

// sine wave, imitating an organ
[inline]
fn organ(freq f32, time f32, amp f32) f32 {
	return math.sinf(audio.tau * time * freq) * amp
		+ math.sinf(audio.tau * time * freq * 3 / 2) * amp / 5
}

[inline]
// triangle wave, imitating an organ
fn torgan(freq f32, time f32, amp f32) f32 {
	t := time * freq
	return f32(2 * math.abs(2 * (t - int(t) - 0.5)) - 1) * amp
		+ f32(2 * math.abs(2 * (t * 3 / 2 - int(t * 3 / 2) - 0.5)) - 1) * amp / 10
}

fn (c &Context) next(mut note Note, time f32) f32 {
	if !note.paused {
		note.step++
		return c.next_fn(note.freq, time, note.damp())
	} else if note.step >= 0 {
		note.step--
		return c.next_fn(note.freq, time, note.damp())
	}
	return 0
}

[inline]
fn (n Note) damp() f32 {
	if n.step < 200 { return n.vol / 4 }
	r := f32(saudio.sample_rate()) / 2
	return f32((n.vol * r / 2) / (n.step + r)) + math.sinf(f32(n.step) / 10) * 0.003 // slight vibrato
}

pub struct Context {
mut:
	next_fn NextFn
	notes   [128]Note
	t       f32
}

const damp_rate = 4

[inline]
pub fn (mut ctx Context) play(midi byte, volume f32) {
	ctx.notes[midi].paused = false
	ctx.notes[midi].vol = volume / f32(damp_rate)
	ctx.notes[midi].step = 1
}

[inline]
pub fn (mut ctx Context) pause(midi byte) {
	ctx.notes[midi].paused = true
	ctx.notes[midi].step = 1000
}

fn clamp(x f64, lowerlimit f64, upperlimit f64) f64 {
	if x < lowerlimit {
		return lowerlimit
	}
	if x > upperlimit {
		return upperlimit
	}
	return x
}

fn audio_cb(mut buffer &f32, num_frames int, num_channels int, mut ctx Context) {
	mut mc := f32(0.0)
	frame_ms := 1.0 / f32(saudio.sample_rate())
	unsafe {
		for frame in 0 .. num_frames {
			for ch in 0 .. num_channels {
				idx := frame * num_channels + ch
				buffer[idx] = 0
				for i, note in ctx.notes {
					if note.step > 0 {
						buffer[idx] += ctx.next(mut ctx.notes[i], ctx.t)
					}
				}
				c := buffer[idx]
				ac := if c < 0 { -c } else { c }
				if mc < ac {
					mc = ac
				}
			}
			ctx.t += frame_ms
		}
		if mc < 1.0 {
			return
		}
		mut normalizing_coef := 1.0 / mc
		for idx in 0 .. (num_frames * num_channels) {
			buffer[idx] *= normalizing_coef
		}
	}
}

pub enum WaveKind {
	// pure waves
	sine
	square
	triangle
	sawtooth

	// composite functions
	organ
	torgan
}

pub struct Config {
	wave_kind WaveKind
}

pub fn new_context(cfg Config) &Context {
	next_fn := match cfg.wave_kind {
		.sine { sine }
		.square { square }
		.triangle { triangle }
		.sawtooth { sawtooth }

		.organ { organ }
		.torgan { torgan }
	}
	mut ctx := &Context{
		next_fn: next_fn
	}
	for i, mut note in ctx.notes {
		bi := byte(i)
		note.freq = midi2freq(bi)
		note.paused = true
		note.step = 0
	}

	saudio.setup(
		user_data: ctx
		stream_userdata_cb: audio_cb
		buffer_frames: 128
	)
	return ctx
}
