require 'spec_helper'

describe CompoundLog do
  subject { Factory(:compound_log) }

  it { should have_many :logs }
  it { CompoundLog.should respond_to(:current_compostable).with(2).arguments }
  it { CompoundLog.new.should respond_to(:compound!).with(2).argument }

  context "when deleting compound log" do
    before do
      @log = Factory(:log)
      subject.logs << @log
    end

    it "should delete successfully" do
      subject.destroy.should == subject
    end

    it "should delete all compounded logs" do
      expect {
        subject.destroy
      }.should change(Log, :count).by(-2)
    end
  end

  context "finder" do
    before do
      @compounded_log_friendships = []
      @compounded_log_course = []
      @compounded_log_user = []

      3.times do
        @compounded_log_user << Factory(:compound_log)
        @compounded_log_course << Factory(:compound_log,
                                          :logeable_type => Course.to_s)
        @compounded_log_friendships << Factory(:compound_log,
                                               :logeable_type => Friendship.to_s )
      end
    end

    it "retrieves compound logs with especified logeable type" do
      CompoundLog.by_logeable_type('Friendship').should == @compounded_log_friendships
      CompoundLog.by_logeable_type('User').should == @compounded_log_user
      CompoundLog.by_logeable_type('User').count.should == 3
    end
  end

  describe :current_compostable do
    context "when people are getting friends" do
      before do
        @robert = Factory(:user, :login => 'robert_baratheon')
        @ned = Factory(:user, :login=> 'eddard_stark')
      end

      context "and there aren't compound logs" do
        it "should create a new one" do
          expect {
            ActiveRecord::Observer.with_observers(:friendship_observer,
                                                  :log_observer) do
              @robert.be_friends_with(@ned)
              @ned.be_friends_with(@robert)
            end
          }.should change(CompoundLog, :count).by(2)
          # One compound for each statusable(user)
        end
      end

      context "and a compound log already exists" do
        before do
          @cercei = Factory(:user, :login => 'cercei_lannister')

          ActiveRecord::Observer.with_observers(:friendship_observer,
                                                :log_observer) do
            @robert.be_friends_with(@ned)
            @ned.be_friends_with(@robert)
          end
        end

        it "should include recently created logs" do
          @robert_compound = CompoundLog.where(:user_id => @robert.id).last
          expect {
            ActiveRecord::Observer.with_observers(:friendship_observer,
                                                  :log_observer) do
              @robert.be_friends_with(@cercei)
              @cercei.be_friends_with(@robert)
              @robert_compound.reload
            end
          }.should change(@robert_compound.logs, :count).from(1).to(2)
        end

        context "but it's ttl has expired" do
          before do
            @robert_compound = CompoundLog.where(:user_id => @robert.id).last
            @robert_compound.compound_visible_at = 2.day.ago
            @robert_compound.save
          end

          it "should create a new compound log for statusable" do
            expect {
              ActiveRecord::Observer.with_observers(:friendship_observer,
                                                    :log_observer) do
                @robert.be_friends_with(@cercei)
                @cercei.be_friends_with(@robert)
              end
            }.should change(CompoundLog, :count).by(2)
            CompoundLog.where(:user_id => @robert.id).count.should == 2
            CompoundLog.where(:user_id => @cercei.id).count.should == 1
          end
        end

        context "and it has the minimum number of logs (4) to being visible" do
          before do
            @tyrion = Factory(:user, :login => 'tyrion_lannister')
            @jhon = Factory(:user, :login => 'jhon_arryn')
            @loras = Factory(:user, :login => 'loras_tyrel')

            ActiveRecord::Observer.with_observers(:friendship_observer,
                                                  :log_observer) do
              @robert.be_friends_with(@cercei)
              @cercei.be_friends_with(@robert)

              @robert.be_friends_with(@tyrion)
              @tyrion.be_friends_with(@robert)

              @robert.be_friends_with(@jhon)
              @jhon.be_friends_with(@robert)

              @robert.be_friends_with(@loras)
              @loras.be_friends_with(@robert)
            end
            @robert_compounds = CompoundLog.where(:user_id => @robert.id)
          end

          it "just have one compoundLog" do
            @robert_compounds.count.should == 1
          end

          it "should contain 5 or more logs" do
            @robert_compounds.last.logs.count.should > 4
          end

          it "should be visible" do
            @robert_compounds.last.compound_visible_at.should_not be_nil
            @robert_compounds.last.compound.should be_false
            # display on view
          end
        end
      end
    end # context "when people are getting friends"

    context "when people are enrolling to courses" do
      before do
        @course = Factory(:course)
        @pycelle = Factory(:user, :login => 'meistre_pycelle')
      end

      context "and there aren't compound logs" do
        it "should create a new one" do
          expect {
            ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                  :log_observer) do
              jaime = Factory(:user, :login => "jaime_lannister")
              @course.join(jaime)
            end
          }.should change(CompoundLog, :count).by(1)
        end
      end

      context "and a compound log already exists" do
        before do
          ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                :log_observer) do
            @course.join(@pycelle)
            @pycelle_compounds = CompoundLog.where(:user_id => @pycelle.id)
            @pycelle_compound = @pycelle_compounds.last
          end
        end

        it "should include new log into existing compound log" do
          course = Factory(:course, :name => "game of thrones")
          expect {
            ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                  :log_observer) do
              course.join(@pycelle)
              @pycelle_compound.reload
            end
          }.should change(@pycelle_compound.logs, :count).from(1).to(2)
        end

        context "but ttl has expired" do
          before do
            ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                  :log_observer) do
              @course.join(@pycelle)
            end
            @pycelle_compound = CompoundLog.where(:user_id => @pycelle.id).last
            @pycelle_compound.compound_visible_at = 2.day.ago
            @pycelle_compound.save
          end

          it "should create a new compound log for statusable" do
            course = Factory(:course)
            expect {
              ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                    :log_observer) do
                course.join(@pycelle)
              end
            }.should change(CompoundLog, :count).by(1)
            CompoundLog.where(:user_id => @pycelle.id).count.should == 2
          end
        end

        context "and it has the minimum number of logs (4) to being visible" do
          before do
            @courses = (1..5).collect { Factory(:course) }
            @aemon = Factory(:user, :login => "aemon_targaryen")

            ActiveRecord::Observer.with_observers(:user_course_association_observer,
                                                  :log_observer) do
              @courses.each { |course| course.join(@aemon) }
            end
            @aemon_compounds = CompoundLog.where(:user_id => @aemon.id)
          end

          it "just have one compoundLog" do
            @aemon_compounds.count.should == 1
          end

          it "should contain 5 or more logs" do
            @aemon_compounds.last.logs.count.should > 4
          end

          it "should be visible" do
            @aemon_compounds.last.compound_visible_at.should_not be_nil
            @aemon_compounds.last.compound.should be_false
            # display on view
          end
        end
      end
    end # context "when people are enrolling to courses"
  end
end
