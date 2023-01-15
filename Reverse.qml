//===========================================================================
// 
// Copyright (C) 2023 Roshni Dave (nngngn)
// 
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 3
//  as published by the Free Software Foundation
//===========================================================================

import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.Reverse"
    description: "reverses selected notes"
    version: "1.1"

    function elementObject(track, pitches, tpcs, dur, tupdur, ratio) {
        this.track = track;
        this.pitches = pitches;
        this.tpcs = tpcs;
        this.dur = dur;
        this.tupdur = tupdur;
        this.ratio = ratio;
    }

    function activeTracks() {
        var tracks = [];
        for(var i = 0; i < curScore.selection.elements.length; i++) {
            var e = curScore.selection.elements[i];
            if(i == 0) {
                tracks.push(e.track);
                var previousTrack = e.track;
            }
            if(i > 0) {
                if(e.track != previousTrack) {
                    tracks.push(e.track);
                    previousTrack = e.track;
                }
            }
        }
        return tracks;
    }

    function dotheReverse() {
        // initialize tick variables
        var startTick;
        var endTick;

        // initialize loop object variables
        var pitches = [];
        var tpcs = [];
        var dur = [];
        var tupdur = [];
        var ratio = [];
        var thisElement = []; // the container for chord/note/rest data
        var theReverse = []; // the container for the full selection

        // initialize cursor
        var cursor = curScore.newCursor();

        // check for selection
        cursor.rewind(1); // rewind cursor to beginning of selection to avoid last measure bug
        if(!cursor.segment) {
            console.log("no selection");
            Qt.quit; // quit if no selection
        }

        // get selection start and end ticks
        startTick = cursor.tick; // get tick at beginning of selection
        cursor.rewind(2); // go to end of selection
        endTick = cursor.tick; // get tick at end of selection
        if(endTick === 0) { // if last measure selected,
            endTick = curScore.lastSegment.tick; // get last tick of score instead
        }

        // get active tracks
        var tracks = activeTracks();

        cursor.rewind(1); // go to beginning of selection before starting the loop

        // go through selection and copy elements to an object
        for(var trackNum in tracks) {
            cursor.track = tracks[trackNum]; // set staff index

            // begin loop
            while(cursor.segment && cursor.tick < endTick) {
                var e = cursor.element; // current chord, note, or rest at cursor

                // get note/rest durations first
                if(e.tuplet) { // tuplets are a special case
                    tupdur.push(e.tuplet.globalDuration.numerator);
                    tupdur.push(e.tuplet.globalDuration.denominator);
                    ratio.push(e.tuplet.actualNotes);
                    ratio.push(e.tuplet.normalNotes);
                }
                dur.push(e.duration.numerator);
                dur.push(e.duration.denominator);

                // get note  data
                if(e.type == Element.CHORD) {
                    var notes = e.notes; // get all notes in the chord
                    for(var noteLoop = 0; noteLoop < notes.length; noteLoop++) {
                        var note = notes[noteLoop];
                        pitches.push(note.pitch);
                        tpcs.push(note.tpc);
                    }
                }

                // create note object with given data
                thisElement = new elementObject(tracks[trackNum], pitches, tpcs, dur, tupdur, ratio);
                theReverse.push(thisElement); // push note object into selection array

                // reset loop object variables
                pitches = [];
                tpcs = [];
                dur = [];
                tupdur = [];
                ratio = [];

                cursor.next(); // advance the cursor (to stop infinite loop)
            }
            if(cursor.tick == endTick && trackNum < tracks.length) {
                cursor.rewind(1); // rewind to get additional voices
            }
        }

        // must rewind to clear...
        cursor.rewind(1);

        // clear selection
        for(var trackNum in tracks) {
            cursor.track = tracks[trackNum];
            while(cursor.segment && cursor.tick < endTick) {
                var e = cursor.element;
                if(e.tuplet) {
                    removeElement(e.tuplet); // you have to specifically remove tuplets
                } else {
                    removeElement(e);
                }
                cursor.next(); // advance cursor
            }
            if(cursor.tick == endTick && trackNum < tracks.length) {
                cursor.rewind(1); // rewind to get additional voices
            }
        }

        cursor.rewind(1); // start
        theReverse.reverse(); // reversing the array
        var tupReset = 0; // need a reset value defined for consecutive tuplets

        // write reverse
        for(var i = 0; i < theReverse.length; i++) {
            var curTrack = theReverse[i].track; // get the current track

            // rewind if change in voice
            if(i > 0) { // but don't do it until the second loop to avoid infinite loop
                if(curTrack != theReverse[i-1].track) {
                    cursor.rewindToTick(startTick);
                    // rewind(1) doesn't work anymore after clearing the selection
                    // so use rewindToTick(startTick)
                }
            }

            cursor.track = curTrack; // set as current track

            cursor.setDuration(theReverse[i].dur[0], theReverse[i].dur[1]);

            var pitches = theReverse[i].pitches; // get the pitches array
            var tpcs = theReverse[i].tpcs; // get the tpcs array

            // if a pitch array exists, then write note and tpc data
            if(pitches.length) {
                for(var pitchLoop = 0; pitchLoop < pitches.length; pitchLoop++) {
                    // if more than one pitch, write chord
                    if(pitchLoop > 0 && pitchLoop < pitches.length) {
                        cursor.prev(); // go back one
                        cursor.addNote(pitches[pitchLoop], true); // add the additional pitch
                        cursor.prev(); // go back one (again)
                        cursor.element.notes[pitchLoop].tpc = tpcs[pitchLoop]; // set the tpc
                        cursor.next();
                    } else {
                        // for single notes
                        var noteTick = cursor.tick; // get the tick
                        cursor.addNote(pitches[pitchLoop]); // write the note
                        cursor.rewindToTick(noteTick); // rewind to noteTick
                        cursor.element.notes[pitchLoop].tpc = tpcs[pitchLoop]; // set the tpc
                        cursor.next(); // manually advance cursor
                    }
                }
            } else { // rest if there aren't pitches
                // weird bug when on voices 2, 3, 4 the cursor advances twice
                var restTick = cursor.tick; // get the tick
                cursor.addRest(); // write the rest
                cursor.rewindToTick(restTick); // rewind to restTick
                cursor.next(); // manually advance cursor
            }

            // if tuplet ratio exists, then go back one and convert note to tuplet
            if(theReverse[i].ratio[0] && tupReset === 0) { // only on the first tuplet element
                cursor.prev(); // go back one
                // create the tuplet
                cursor.addTuplet(
                    fraction(theReverse[i].ratio[0], theReverse[i].ratio[1]), // the ratio
                    fraction(theReverse[i].tupdur[0], theReverse[i].tupdur[1]) // the duration
                );
                cursor.next(); // go forward one
            }

            // iterate through tuplet notes and reset counter when done
            if(theReverse[i].ratio[0] && tupReset < theReverse[i].ratio[0] - 1) {
                tupReset++;
            } else {
                tupReset = 0;
            }
        }
    }

    onRun: {
        dotheReverse();
        Qt.quit();
    }
}
