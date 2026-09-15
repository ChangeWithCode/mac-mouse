'use strict';
/* Faithful port of Sources/GlideCore/Input/ChordRecognizer.swift. */

const key = set => [...set].sort((a, b) => a - b).join(',');
const eq = (a, b) => key(a) === key(b);

class ChordRecognizer {
  static maxClickCount = 4;

  constructor() {
    this.holdThreshold = 0.2;
    this.multiClickWindow = 0.25;
    this.dragThreshold = 5.0;
    this.isBound = () => false;
    this.hasAnyBinding = () => false;

    this.held = new Set();
    this.group = new Set();
    this.groupStart = 0;
    this.dragDistance = 0;
    this.continuousTrigger = null;
    this.holdFired = false;
    this.pendingClicks = null;
  }

  press(button, time) {
    if (!this.hasAnyBinding(button)) return [{ t: 'passThrough', button }];
    const events = [];

    const withButton = new Set([...this.group, button]);
    if (this.pendingClicks && !eq(this.pendingClicks.group, withButton)) {
      events.push(...this._emitClick(this.pendingClicks.group, this.pendingClicks.count));
      this.pendingClicks = null;
    }

    if (this.held.size === 0 && this.continuousTrigger === null) {
      this.group = new Set();
      this.groupStart = time;
      this.dragDistance = 0;
      this.holdFired = false;
    }
    this.held.add(button);
    this.group.add(button);

    if (this.continuousTrigger && !eq(this.continuousTrigger.buttons, this.group)) {
      events.push({ t: 'end', trigger: this.continuousTrigger });
      this.continuousTrigger = null;
      this.holdFired = false;
      this.groupStart = time;
    }
    return events;
  }

  release(button, time) {
    if (!this.hasAnyBinding(button)) return [{ t: 'passThrough', button }];
    this.held.delete(button);
    const events = [];

    if (this.continuousTrigger && this.held.size === 0) {
      events.push({ t: 'end', trigger: this.continuousTrigger });
      this.continuousTrigger = null;
      this.holdFired = false;
      this.group = new Set();
      return events;
    }
    if (this.held.size > 0) return events;

    if (this.holdFired) { this.holdFired = false; this.group = new Set(); return events; }

    const resolved = this.group;
    this.group = new Set();
    const count = ((this.pendingClicks && eq(this.pendingClicks.group, resolved)) ? this.pendingClicks.count : 0) + 1;

    let longerExists = false;
    // Mirrors ChordRecognizer.maxClickCount. The Swift uses stride here because
    // a ClosedRange would be inverted (and trap) once count reaches 4.
    for (let n = count + 1; n <= ChordRecognizer.maxClickCount; n++) {
      if (this.isBound({ buttons: resolved, kind: { click: n } })) { longerExists = true; break; }
    }
    if (longerExists) {
      this.pendingClicks = { group: resolved, count, deadline: time + this.multiClickWindow };
    } else {
      this.pendingClicks = null;
      events.push(...this._emitClick(resolved, count));
    }
    return events;
  }

  move(distance, time) {
    if (this.held.size === 0 || this.continuousTrigger !== null || this.holdFired) return [];
    this.dragDistance += distance;
    if (this.dragDistance < this.dragThreshold) return [];
    const trigger = { buttons: new Set(this.group), kind: { drag: true } };  // copy: Swift Set is a value type
    if (!this.isBound(trigger)) return [];
    this.continuousTrigger = trigger;
    this.holdFired = true;
    return [{ t: 'begin', trigger }];
  }

  tick(now) {
    const events = [];
    if (this.held.size > 0 && !this.holdFired && this.continuousTrigger === null &&
        now - this.groupStart >= this.holdThreshold) {
      const trigger = { buttons: new Set(this.group), kind: { hold: true } };  // copy: Swift Set is a value type
      if (this.isBound(trigger)) {
        this.continuousTrigger = trigger;
        this.holdFired = true;
        events.push({ t: 'begin', trigger });
      } else {
        this.holdFired = true;
        events.push(...this._fallback(this.group));
      }
    }
    if (this.pendingClicks && now >= this.pendingClicks.deadline) {
      events.push(...this._emitClick(this.pendingClicks.group, this.pendingClicks.count));
      this.pendingClicks = null;
    }
    return events;
  }

  _emitClick(group, count) {
    const trigger = { buttons: group, kind: { click: count } };
    if (this.isBound(trigger)) return [{ t: 'fire', trigger }];
    for (let n = count - 1; n >= 1; n--) {
      const c = { buttons: group, kind: { click: n } };
      if (this.isBound(c)) return [{ t: 'fire', trigger: c }];
    }
    return this._fallback(group);
  }

  _fallback(group) {
    return [...group].sort((a, b) => a - b).map(b => ({ t: 'synthesizeClick', button: b }));
  }
}

/* Build an isBound/hasAnyBinding pair from a list of "3:click:1" style specs. */
function bindings(specs) {
  const set = new Set(specs);
  const isBound = trig => {
    const b = key(trig.buttons);
    if (trig.kind.hold) return set.has(`${b}:hold`);
    if (trig.kind.drag) return set.has(`${b}:drag`);
    return set.has(`${b}:click:${trig.kind.click}`);
  };
  const hasAnyBinding = button =>
    [...set].some(s => s.split(':')[0].split(',').includes(String(button)));
  return { isBound, hasAnyBinding };
}

module.exports = { ChordRecognizer, bindings, key };
